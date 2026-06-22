--  Render every fleet host's NativeLink config. Returns a List {host, json} the
--  render app writes to nativelink/out/<host>.json (committed, IFD-free).
let fleet = ./fleet.dhall

let schema = ./schema.dhall

let Prelude = schema.Prelude

in  Prelude.List.map
      fleet.HostDef.Type
      { host : Text, json : Text }
      (\(h : fleet.HostDef.Type) -> { host = h.name, json = fleet.renderFor h })
      fleet.hosts
