# A split host's processes must PARTITION its monolithic config: merged, they
# are the same stores, schedulers, servers and workers (order aside), and no
# name is defined twice. Input: the monolithic config, with --slurpfile parts
# holding each process config. Emits {ok, why}.
def byname: sort_by(.name // tostring);
def merged($k): [$parts[] | .[$k] // [] | .[]];
def dupes($k): merged($k) | map(.name // empty) | group_by(.) | map(select(length > 1) | .[0]);
. as $mono
| [ "stores", "schedulers", "servers", "workers" ] as $keys
| [ $keys[] | select((merged(.) | byname) != (($mono[.] // []) | byname)) ] as $differ
| [ $keys[] | dupes(.)[] ] as $dup
| [ $parts[] | .global ] | unique as $globals
| { ok: (($differ | length) == 0 and ($dup | length) == 0 and $globals == [ $mono.global ])
  , why: { differ: $differ, duplicated: $dup, globals: $globals }
  }
