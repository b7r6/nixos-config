# btrfs ENOSPC deadlock — when the disk is too full to delete

`rm` hangs and won't die. Every process that touches `/` stalls. The disk is nearly full but you're
*trying to free it* — and can't. This is a btrfs copy-on-write failure mode: on a full filesystem,
**deleting a file is itself a write**, so `rm` needs to reserve space it can't get and parks in
uninterruptible sleep forever. Worked here against the real incident on `ultraviolence`
(2026-07-18), where a 2.4 TB `buck-out` build tree and a wedged `rm` had the box pinned.

______________________________________________________________________

## Symptom

- `rm -rf <big-tree>` (or any writer) hangs and ignores `SIGKILL` — `kill -9` does nothing.
- The process sits in uninterruptible (`D`) state; its kernel wait channel is `handle_reserve_ticket`.
- Other daemons touching the same fs (here `nix-daemon`) go `D` too. The box feels alive (ssh works)
  until you touch `/`.

```bash
ps -eo pid,stat,wchan:24,cmd | awk '$2 ~ /D/'
#   568465 D+  handle_reserve_ticket   rm -rf …/buck-out/
#   558311 Dsl -                       nix-daemon
```

A `D`-state task is blocked in the kernel and **cannot be signalled** — not even `SIGKILL` lands
until the wait returns. The only ways out are (a) give it the space it's waiting for, or (b) reboot.

______________________________________________________________________

## Why it happens

btrfs is copy-on-write: mutating the filesystem — **including removing extents** — writes new
metadata b-tree nodes before it frees the old ones. That write needs a *metadata reservation*. Two
numbers decide whether it can be granted, and `df` shows neither:

```bash
sudo btrfs filesystem usage /
```
```
Device unallocated:   1.02MiB                  ← raw space not yet carved into a chunk
Metadata,DUP:  42.01GiB used 41.36 (98.47%)    ← the metadata chunk pool…
Data,single:   3.55TiB  used  3.48 (97.94%)    ← …and data, both nearly full
Global reserve: 512.00MiB used 0.00B
```

btrfs allocates raw device space into fixed **chunks**, separately for data and metadata. When the
metadata pool is full it grows by allocating a *new* metadata chunk from **unallocated** device
space. Here that's the trap:

- **Metadata is 98% full** → the reservation for `rm`'s CoW write doesn't fit in the current pool.
- **Device unallocated is ~0** → every byte is already committed to a data or metadata chunk, so
  btrfs **cannot allocate a new metadata chunk** to grow the pool.

So the reservation ticket is queued and never satisfied (`handle_reserve_ticket`), and `rm` blocks
forever. `df` said "98% full, 75 GB free," which looks survivable; the real killer is the
`Device unallocated: 1 MiB` line. The 512 MiB global reserve is why *small* deletes sometimes still
squeak through — a large tree removal exhausts it.

______________________________________________________________________

## Recovery — reclaim unallocated space with balance

The fix is to hand raw space back to the "unallocated" pool so metadata can grow, at which point the
stuck `rm` **wakes on its own** and finishes. You do that by balancing mostly-empty *data* chunks:
btrfs relocates the little data they hold into the free space of other chunks and returns the emptied
chunk to unallocated.

Start at the cheapest threshold and climb. `-dusage=N` only touches data chunks under N% full, so
`0` is nearly free (relocates only fully-empty chunks) and higher values do more work:

```bash
sudo btrfs balance start -dusage=0  /     # empty chunks only — cheap
sudo btrfs balance start -dusage=5  /     # climb if 0 freed nothing
sudo btrfs balance start -dusage=10 /

sudo btrfs balance status /               # watch, from another shell
sudo btrfs balance cancel /               # safe to abort mid-run
```

On the real incident, `-dusage=0` relocated **0 of 3686** chunks (no fully-empty chunks existed);
`-dusage=5` relocated **4** chunks, which returned **1 MiB → 1.00 GiB** unallocated and dropped
metadata from 98.5% → 94.7%. That was enough: the wedged `rm` flipped `D → R+` and resumed deleting
with no further intervention. Deletes *net-release* metadata (they drop b-tree nodes), so once one is
moving it is self-sustaining — it won't re-wedge.

> **Balance itself needs a sliver of metadata to run**, so on a truly-wedged fs even `-dusage=0` can
> block. Start low; the 512 MiB global reserve is held back for exactly this and usually covers it.
> If balance *does* wedge, reboot (below).

______________________________________________________________________

## The reflink trap — why deleting the big tree freed almost nothing

Deleting the 2.4 TB `buck-out` freed the metadata (the file entries) but only **~20 GB** of actual
data — not 2.4 TB. `df` barely moved. The cause: buck2's materializer **reflink-copies** `nix_build`
content dirs and dedups outputs, so those files share extents with `/nix/store` (and each other).
`du` counts each file's blocks independently, so it reports the *sum of references* (2.1 TB) while
the extents stay live as long as anything else — the store — still points at them.

Lesson: **`du` overcounts shared extents; `btrfs filesystem usage` is the truth.** To find space you
can actually reclaim, look past reflinked build trees. On the incident the real headroom came from
docker, not the build tree:

```bash
sudo docker system df        # 286 GB reclaimable — 89% of images unused
sudo docker image prune -a   # → took the fs from 86 GB to 534 GB free
```

`nix-store --gc --print-dead` reported **0** dead paths (the store was fully pinned by GC roots), so
a nix GC would have freed nothing either — another reason the win was docker.

______________________________________________________________________

## Escalation — reboot if balance itself wedges

If even `-dusage=0` blocks (metadata too tight to relocate anything), reboot to clear the stuck
transaction and the `D`-state process:

- Expect shutdown to **stall on "unmounting /"** — the wedged `rm` can't be reaped, so the unmount
  can't complete. Give systemd its stop timeout, or force it:

  ```bash
  echo b | sudo tee /proc/sysrq-trigger    # immediate reboot (SysRq-b)
  ```

- btrfs is journaled; it replays its log on the next mount, so a hard reset here is safe. **On the
  fresh mount, run `btrfs balance start -dusage=0 /` before rebuilding anything** — the fs is still
  near-full and will re-wedge if you refill it first.

______________________________________________________________________

## Prevention

- **Monitor `Device unallocated`, not `df`.** `df` at 98% looks normal; `Device unallocated`
  approaching zero is the actual cliff. Alert on it, and on metadata `used%`.
- **Keep the fs off 100%.** btrfs degrades badly in the last few percent — leave real slack.
- **Balance periodically.** There is no NixOS built-in balance timer (`services.btrfs.autoScrub` is
  *scrub*, not balance). A weekly `btrfs balance start -dusage=50 /` systemd timer keeps unallocated
  space healthy so a delete never dead-ends.
- **Contain build-output growth.** buck2 `buck-out`, cargo `target`, and docker are the usual
  offenders. Put throwaway build trees on their own subvolume (droppable as a unit) and GC them on a
  schedule; don't let one tree reflink-balloon to terabytes unnoticed.
- **Size cleanups with the right tool.** A 2 TB `du` on a buck2/nix tree may be a few GB of unique
  data — or the reverse. Estimate reclaim by `btrfs filesystem usage`, never `du`.

See the copy-paste form in [Runbooks §F](./runbooks.md#f--btrfs-is-too-full-to-delete-enospc-deadlock).
