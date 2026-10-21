--  Render every fleet host's NativeLink PROCESSES: List {host, process, json},
--  one row per process (fleet.processesFor). A monolithic host is one row named
--  "nativelink", the same JSON render-all.dhall gives the fork's module; a
--  split host has one row per role, run as one unit each by ../split.nix.
let fleet = ./fleet.dhall

let schema = ./schema.dhall

let Prelude = schema.Prelude

let Row = { host : Text, process : Text, json : Text }

in  Prelude.List.concatMap
      fleet.HostDef.Type
      Row
      ( \(h : fleet.HostDef.Type) ->
          Prelude.List.map
            { process : Text, json : Text }
            Row
            ( \(p : { process : Text, json : Text }) ->
                { host = h.name, process = p.process, json = p.json }
            )
            (fleet.renderProcessesFor h)
      )
      fleet.enabledHosts
