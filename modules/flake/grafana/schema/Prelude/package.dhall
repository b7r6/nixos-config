--  minimal prelude for the grafana dashboard renderer.
--  only the functions we actually use — no network fetch required.

-- listMap isn't a builtin; implement via List/build + List/fold
let listMap =
      \(a : Type) ->
      \(b : Type) ->
      \(f : a -> b) ->
      \(xs : List a) ->
        List/build
          b
          ( \(list : Type) ->
            \(cons : b -> list -> list) ->
            \(nil : list) ->
              List/fold a xs list (\(x : a) -> \(acc : list) -> cons (f x) acc) nil
          )

let JSON =
      -- Dhall JSON encoding (Church-encoded)
      let Ty =
            forall (JSON : Type) ->
            forall ( json
                   : { array : List JSON -> JSON
                     , bool : Bool -> JSON
                     , double : Double -> JSON
                     , integer : Integer -> JSON
                     , null : JSON
                     , natural : Natural -> JSON
                     , object : List { mapKey : Text, mapValue : JSON } -> JSON
                     , string : Text -> JSON
                     }
                   ) ->
              JSON

      let Json = { array : List Ty -> Ty, bool : Bool -> Ty, double : Double -> Ty, integer : Integer -> Ty, null : Ty, natural : Natural -> Ty, object : List { mapKey : Text, mapValue : Ty } -> Ty, string : Text -> Ty }

      let string
          : Text -> Ty
          = \(x : Text) ->
            \(JSON : Type) ->
            \(json : { array : List JSON -> JSON, bool : Bool -> JSON, double : Double -> JSON, integer : Integer -> JSON, null : JSON, natural : Natural -> JSON, object : List { mapKey : Text, mapValue : JSON } -> JSON, string : Text -> JSON }) ->
              json.string x

      let natural
          : Natural -> Ty
          = \(x : Natural) ->
            \(JSON : Type) ->
            \(json : { array : List JSON -> JSON, bool : Bool -> JSON, double : Double -> JSON, integer : Integer -> JSON, null : JSON, natural : Natural -> JSON, object : List { mapKey : Text, mapValue : JSON } -> JSON, string : Text -> JSON }) ->
              json.natural x

      let bool
          : Bool -> Ty
          = \(x : Bool) ->
            \(JSON : Type) ->
            \(json : { array : List JSON -> JSON, bool : Bool -> JSON, double : Double -> JSON, integer : Integer -> JSON, null : JSON, natural : Natural -> JSON, object : List { mapKey : Text, mapValue : JSON } -> JSON, string : Text -> JSON }) ->
              json.bool x

      let null
          : Ty
          = \(JSON : Type) ->
            \(json : { array : List JSON -> JSON, bool : Bool -> JSON, double : Double -> JSON, integer : Integer -> JSON, null : JSON, natural : Natural -> JSON, object : List { mapKey : Text, mapValue : JSON } -> JSON, string : Text -> JSON }) ->
              json.null

      let object
          : List { mapKey : Text, mapValue : Ty } -> Ty
          = \(xs : List { mapKey : Text, mapValue : Ty }) ->
            \(JSON : Type) ->
            \(json : { array : List JSON -> JSON, bool : Bool -> JSON, double : Double -> JSON, integer : Integer -> JSON, null : JSON, natural : Natural -> JSON, object : List { mapKey : Text, mapValue : JSON } -> JSON, string : Text -> JSON }) ->
              json.object
                ( listMap
                    { mapKey : Text, mapValue : Ty }
                    { mapKey : Text, mapValue : JSON }
                    ( \(kv : { mapKey : Text, mapValue : Ty }) ->
                        { mapKey = kv.mapKey, mapValue = kv.mapValue JSON json }
                    )
                    xs
                )

      let array
          : List Ty -> Ty
          = \(xs : List Ty) ->
            \(JSON : Type) ->
            \(json : { array : List JSON -> JSON, bool : Bool -> JSON, double : Double -> JSON, integer : Integer -> JSON, null : JSON, natural : Natural -> JSON, object : List { mapKey : Text, mapValue : JSON } -> JSON, string : Text -> JSON }) ->
              json.array (listMap Ty JSON (\(x : Ty) -> x JSON json) xs)

      in  { Type = Ty, string, natural, bool, null, object, array }

let ListUtils =
      { map =
          \(a : Type) ->
          \(b : Type) ->
          \(f : a -> b) ->
          \(xs : List a) ->
            listMap a b f xs
      , foldLeft =
          \(a : Type) ->
          \(acc : Type) ->
          \(xs : List a) ->
          \(init : acc) ->
          \(step : acc -> a -> acc) ->
            ( List/fold
                a
                xs
                (acc -> acc)
                (\(x : a) -> \(k : acc -> acc) -> \(z : acc) -> k (step z x))
                (\(z : acc) -> z)
            )
              init
      }

let NaturalUtils =
      { greaterThan =
          -- a > b iff (a - b) != 0, where Natural/subtract x y = max(0, y - x)
          \(a : Natural) ->
          \(b : Natural) ->
            Natural/isZero (Natural/subtract b a) == False
      }

in  { JSON, List = ListUtils, Natural = NaturalUtils }
