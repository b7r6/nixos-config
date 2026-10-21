# A split host's processes must PARTITION its monolithic config: merged, they
# are the same stores, schedulers, servers and workers (order aside), and no
# name is defined twice. A split host may run several workers where the
# monolith has one, so worker processes are compared with the per-worker
# fields blanked (fast tier paths and size, work directory, slots): they must
# all be that same worker, and the monolith's. Input: the monolithic config,
# with --slurpfile parts holding each process config. Emits {ok, why}.
def byname: sort_by(.name // tostring);

# Blank what legitimately differs between workers: the local worker's work
# directory and slots, and its fast_slow store's filesystem paths and size.
def perworker:
  ((.workers // []) | map(.local.cas_fast_slow_store)) as $fast
  | .stores |= map(
      if (.name | IN($fast[])) then
        walk(if type == "object" and has("content_path") then
               .content_path = null | .temp_path = null | .eviction_policy = null
             else . end)
      else . end)
  | .workers |= (if . == null then null else map(.local |= (.work_directory = null | .max_inflight_tasks = null)) end);

($parts | map(select(has("workers")) | perworker) | unique) as $workerShapes
| ([$parts[] | select(has("workers") | not)] + $workerShapes) as $distinct
| def merged($k): [$distinct[] | .[$k] // [] | .[]];
  def dupes($k): merged($k) | map(.name // empty) | group_by(.) | map(select(length > 1) | .[0]);
  (. | perworker) as $mono
| [ "stores", "schedulers", "servers", "workers" ] as $keys
| [ $keys[] | select((merged(.) | byname) != (($mono[.] // []) | byname)) ] as $differ
| [ $keys[] | dupes(.)[] ] as $dup
| [ $parts[] | .global ] | unique as $globals
| { ok: (($workerShapes | length) <= 1 and ($differ | length) == 0 and ($dup | length) == 0 and $globals == [ $mono.global ])
  , why: { worker_shapes: ($workerShapes | length), differ: $differ, duplicated: $dup, globals: $globals }
  }
