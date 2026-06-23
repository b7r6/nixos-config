-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                   // hypermodern // coredns // zone renderer
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--   "It was a place of dense information, a sketch of the host system's
--    architecture, and she read it the way a sailor reads weather."
--
--                                                       — Mona Lisa Overdrive
--
-- Render the typed Dhall topology registry to a BIND zone for CoreDNS.
--
-- DNS is intolerant of silent-wrong output: a bad zone strands the very network
-- we deploy over (lose the names → lose ssh → drive to the box). So this program
-- is built to FAIL LOUDLY rather than emit a plausible-but-broken zone:
--
--   * the registry is decoded DIRECTLY via Dhall.input — no dhall-to-json hop,
--     no hand-mirrored JSON schema. Dhall's decode is structurally strict, so a
--     schema field this type doesn't track is a decode ERROR, never a silent drop.
--   * the transform (registry -> zone) is a TOTAL pure function.
--   * semantic DNS invariants are ASSERTED (Validation, accumulating ALL errors):
--       - the NS-glue self-IP is a well-formed dotted-quad
--       - the zone is non-empty (at least one A record)
--       - no duplicate A owner-names
--       - every service CNAME target resolves to an A record in the zone
--       - no service tag is claimed by more than one host
--     Any violation => the program exits non-zero WITHOUT writing a zone.

module Main (main) where

import           Data.List           (sort, sortOn)
import qualified Data.Map.Strict     as Map
import           Data.Text           (Text)
import qualified Data.Text           as T
import qualified Data.Text.IO        as TIO
import qualified Data.Text.Read      as TR
import           Dhall               (FromDhall, Generic)
import qualified Dhall
import           Options.Applicative
import           System.Exit         (exitFailure)
import           System.IO           (hPutStrLn, stderr)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                          // domain // newtypes
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

newtype Zone = Zone Text
newtype Ipv4 = Ipv4 Text

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                       // registry // decoding
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Faithful mirrors of registry/schema.dhall. Every field present => total decode;
-- a schema change this doesn't track fails at Dhall.input, loudly.

data Host = Host
    { physical      :: Text
    , tailnet       :: Text
    , dc            :: Text
    , logical       :: Text
    , tailnet_ipv4  :: Text
    , lan_ipv4      :: Maybe Text
    , provider_ipv4 :: Maybe Text
    , zone          :: Text
    , role          :: Text
    , services      :: [Text]
    , managed       :: Bool
    }
    deriving stock (Generic, Show)
    deriving anyclass (FromDhall)

data ZoneDecl = ZoneDecl
    { name        :: Text
    , description :: Text
    }
    deriving stock (Generic, Show)
    deriving anyclass (FromDhall)

data Registry = Registry
    { tailnetSuffix  :: Text
    , internalDomain :: Text
    , zones          :: [ZoneDecl]
    , hosts          :: [Host]
    }
    deriving stock (Generic, Show)
    deriving anyclass (FromDhall)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                    // validation (accumulating)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- A tiny accumulating Validation so a bad registry surfaces ALL its problems in
-- one shot, not one-error-per-run. (We avoid a dependency and inline it.)

data V a = Err [Text] | Ok a

instance Functor V where
    fmap _ (Err e) = Err e
    fmap f (Ok a)  = Ok (f a)

instance Applicative V where
    pure = Ok
    Err e1 <*> Err e2 = Err (e1 <> e2)
    Err e <*> Ok _    = Err e
    Ok _ <*> Err e    = Err e
    Ok f <*> Ok a     = Ok (f a)

check :: Bool -> Text -> V ()
check ok msg = if ok then Ok () else Err [msg]

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                          // semantic DNS checks
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

isDottedQuad :: Text -> Bool
isDottedQuad t =
    case T.splitOn "." t of
        [a, b, c, d] -> all octet [a, b, c, d]
        _            -> False
  where
    octet o = case TR.decimal o of
        Right (n, "") -> n >= (0 :: Int) && n <= 255
        _             -> False

-- duplicate elements of a list (each reported once)
dups :: (Ord a) => [a] -> [a]
dups = Map.keys . Map.filter (> 1) . Map.fromListWith (+) . map (,1 :: Int)

-- The full structural validation of the fleet against DNS sanity.
validate :: Zone -> Ipv4 -> [Host] -> V ()
validate (Zone z) (Ipv4 self) hs =
    check
        (isDottedQuad self)
        ("NS-glue self-ip is not a dotted-quad: " <> self)
        *> check
            (not (null aNames))
            "zone has no A records (would strand resolution)"
        *> check
            (null dupNames)
            ("duplicate A owner-names: " <> commas dupNames)
        *> check
            (null danglingCnames)
            ("service CNAME target has no A record in zone: " <> commas danglingCnames)
        *> check
            (null dupTags)
            ("service tag claimed by multiple hosts: " <> commas dupTags)
  where
    aNames = map physical hs
    dupNames = dups aNames
    aNameSet = Map.fromList [(physical h, ()) | h <- hs]
    cnameTargets = [physical h | h <- hs, not (null (services h))]
    danglingCnames = [t | t <- cnameTargets, not (Map.member t aNameSet)]
    dupTags = dups [tag | h <- hs, tag <- services h]
    commas = T.intercalate ", " . sort . map qualify
    qualify x = x <> "." <> z

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                          // render (pure/total)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

renderHeader :: Zone -> Ipv4 -> Int -> Text -> Text
renderHeader (Zone z) (Ipv4 self) ttl serial =
    T.unlines
        [ "$TTL " <> tshow ttl
        , "$ORIGIN " <> z <> "."
        , "@ IN SOA ns." <> z <> ". admin." <> z <> ". ("
        , "    " <> serial <> " ; serial"
        , "    3600          ; refresh"
        , "    1800          ; retry"
        , "    604800        ; expire"
        , "    " <> tshow ttl <> " ; minimum"
        , ")"
        , "@ IN NS ns." <> z <> "."
        , "ns IN A " <> self
        ]

section :: Text -> [Text] -> Text
section title body = T.unlines (("; ── " <> title <> " ──") : body)

renderZone :: Zone -> Ipv4 -> Int -> Text -> [Host] -> Text
renderZone z@(Zone zn) self ttl serial hs =
    T.intercalate
        "\n"
        [ renderHeader z self ttl serial
        , section
            "hosts: <host> → tailnet_ipv4"
            [physical h <> " IN A " <> tailnet_ipv4 h | h <- hs]
        , section
            "LAN: <host>.lan → lan_ipv4 (static-leased wired boxes only)"
            [physical h <> ".lan IN A " <> ip | h <- hs, Just ip <- [lan_ipv4 h]]
        , section
            ("service aliases: <service>." <> zn <> " → host running it")
            -- sorted for determinism
            [ tag <> " IN CNAME " <> host <> "." <> zn <> "."
            | (tag, host) <- sortOn fst [(tag, physical h) | h <- hs, tag <- services h]
            ]
        ]

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                                       // cli
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

data Opts = Opts
    { optSelfIp   :: Text
    , optRegistry :: FilePath
    , optDc       :: Text
    , optTtl      :: Int
    , optSerial   :: Text
    }

optsP :: Parser Opts
optsP =
    Opts
        <$> strOption
            ( long "self-ip"
                <> metavar "IPV4"
                <> help "this resolver's tailnet IPv4 (the `ns IN A` glue record)"
            )
        <*> strOption
            ( long "registry"
                <> metavar "FILE"
                <> value "registry/hosts.dhall"
                <> showDefault
                <> help "path to the topology registry (hosts.dhall)"
            )
        <*> strOption
            ( long "dc"
                <> metavar "DC"
                <> value "sju1"
                <> showDefault
                <> help "DC subdomain: zone = <dc>.<internalDomain>"
            )
        <*> option
            auto
            ( long "ttl"
                <> metavar "SECONDS"
                <> value 300
                <> showDefault
                <> help "zone TTL / SOA minimum"
            )
        <*> strOption
            ( long "serial"
                <> metavar "N"
                <> value "1"
                <> showDefault
                <> help "SOA serial"
            )

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                                      // main
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

main :: IO ()
main = do
    o <-
        execParser $
            info
                (optsP <**> helper)
                (fullDesc <> progDesc "Render the Dhall topology registry to a CoreDNS zone.")

    -- Decode the typed registry directly; drift / malformed input throws here.
    -- inputFile takes a real FILE PATH (input would parse the arg as Dhall source).
    reg <- Dhall.inputFile Dhall.auto (optRegistry o) :: IO Registry

    let z = Zone (optDc o <> "." <> internalDomain reg)
        self = Ipv4 (optSelfIp o)
        hs = hosts reg

    case validate z self hs of
        Err es ->
            die
                ( "refusing to emit zone — topology violates DNS invariants:\n"
                    <> T.unlines (map ("  • " <>) es)
                )
        Ok () -> TIO.putStr (renderZone z self (optTtl o) (optSerial o) hs)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                                     // util
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

tshow :: (Show a) => a -> Text
tshow = T.pack . show

die :: Text -> IO a
die msg = do
    hPutStrLn stderr (T.unpack (T.stripEnd msg))
    exitFailure
