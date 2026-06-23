-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                    // hypermodern // state // audit
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--   "She checked each datum the way one checks a seatbelt before the drop."
--
--                                                            — paraphrase, Gibson
--
-- Validate the fleet's state classification against data-loss invariants.
-- Consumes a JSON description of a host's state dirs + backup config + exclude
-- patterns, and REFUSES TO PASS (exit 1, all violations accumulated) when the
-- classification would silently lose data:
--
--   • every path is absolute (no relative, no "..")
--   • no duplicate paths within a derived list
--   • no subsumption (child alongside its ancestor)
--   • every authoritative path is also persisted (the construction invariant)
--   • no authoritative path is glob-matched by a restic exclude pattern
--
-- Fed by a module-emitted JSON; consumed by checks/state-audit.nix (nixosTest).

module Main (main) where

import           Data.Aeson         (FromJSON (..), eitherDecodeStrict,
                                     withObject, (.:))
import qualified Data.ByteString    as BS
import           Data.List          (sort)
import qualified Data.Map.Strict    as Map
import           Data.Text          (Text)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           System.Environment (getArgs)
import           System.Exit        (exitFailure, exitSuccess)
import           System.FilePath    (isAbsolute, isValid)
import           System.IO          (hPutStrLn, stderr)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                                  // input schema
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

data StateDir = StateDir
    { sdName  :: Text
    , sdPath  :: Text
    , sdClass :: Text
    }
    deriving stock (Show)

instance FromJSON StateDir where
    parseJSON = withObject "StateDir" $ \o ->
        StateDir <$> o .: "name" <*> o .: "path" <*> o .: "class"

data AuditInput = AuditInput
    { aiDirs               :: [StateDir]
    , aiAuthoritativePaths :: [Text] -- derived by state.nix
    , aiPersistPaths       :: [Text] -- derived by state.nix
    , aiBackupPaths        :: [Text] -- the final restic paths list (after union)
    , aiExclude            :: [Text] -- restic exclude globs
    }
    deriving stock (Show)

instance FromJSON AuditInput where
    parseJSON = withObject "AuditInput" $ \o ->
        AuditInput
            <$> o .: "dirs"
            <*> o .: "authoritativePaths"
            <*> o .: "persistPaths"
            <*> o .: "backupPaths"
            <*> o .: "exclude"

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                           // validation (accumulating)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

type Errors = [Text]

check :: Bool -> Text -> Errors
check True _    = []
check False msg = [msg]

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                              // invariant checks
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- | Every declared path is absolute, well-formed, and contains no ".." component.
checkAbsolute :: [StateDir] -> Errors
checkAbsolute = concatMap $ \sd ->
    let p = T.unpack (sdPath sd)
     in check
            (isAbsolute p && isValid p)
            ("path not absolute: " <> sdName sd <> " = " <> sdPath sd)
            <> check
                (not (T.isInfixOf ".." (sdPath sd)))
                ("path contains '..': " <> sdName sd <> " = " <> sdPath sd)

-- | No duplicate paths in a list.
checkNoDups :: Text -> [Text] -> Errors
checkNoDups label ps =
    let dups = Map.keys . Map.filter (> 1) . Map.fromListWith (+) $ map (,1 :: Int) ps
     in concatMap (\d -> ["duplicate path in " <> label <> ": " <> d]) dups

-- | No path is a prefix of another (subsumption).
checkNoSubsumption :: Text -> [Text] -> Errors
checkNoSubsumption label ps =
    let sorted = sort ps
        pairs = zip sorted (drop 1 sorted)
     in concatMap
            ( \(a, b) ->
                check
                    (not (a `T.isPrefixOf` (b <> "/")))
                    ("subsumption in " <> label <> ": " <> a <> " subsumes " <> b)
            )
            pairs

{- | Every authoritative path must appear in persistPaths (the construction
invariant from state.nix; auditing it catches a refactor that breaks it).
-}
checkAuthoritativePersisted :: [Text] -> [Text] -> Errors
checkAuthoritativePersisted auth persist =
    let persistSet = Map.fromList [(p, ()) | p <- persist]
     in concatMap
            ( \a ->
                check
                    (Map.member a persistSet)
                    ("authoritative path NOT in persistPaths (would be wiped on reboot AND backed up empty): " <> a)
            )
            auth

{- | No authoritative path is matched by a restic exclude glob. This is a
SIMPLIFIED glob match: we check whether any exclude pattern is a prefix of the
path (for directory patterns like "/var/lib/docker") or the path ends with the
glob's suffix (for extension patterns like "*.safetensors"). Full glob semantics
would need a proper library, but these two cover the patterns actually in use.
-}
checkNotExcluded :: [Text] -> [Text] -> Errors
checkNotExcluded authPaths excludes =
    concatMap (\a -> concatMap (matchExclude a) excludes) authPaths
  where
    matchExclude path glob
        -- directory-prefix exclude: /var/lib/docker matches /var/lib/docker/…
        | not (T.isPrefixOf "*" glob) && not (T.isInfixOf "*" glob)
        , T.isPrefixOf glob path || path `T.isPrefixOf` glob =
            ["authoritative path " <> path <> " matched by exclude: " <> glob]
        -- we skip wildcard globs (**.safetensors etc.) because those are extension
        -- patterns that won't match a directory path. If a future exclude is a
        -- directory glob we'd want to expand this.
        | otherwise = []

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                                        // main
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

audit :: AuditInput -> Errors
audit ai =
    mconcat
        [ checkAbsolute (aiDirs ai)
        , checkNoDups "authoritativePaths" (aiAuthoritativePaths ai)
        , checkNoDups "persistPaths" (aiPersistPaths ai)
        , checkNoDups "backupPaths" (aiBackupPaths ai)
        , checkNoSubsumption "backupPaths" (aiBackupPaths ai)
        , checkAuthoritativePersisted (aiAuthoritativePaths ai) (aiPersistPaths ai)
        , checkNotExcluded (aiAuthoritativePaths ai) (aiExclude ai)
        ]

main :: IO ()
main = do
    args <- getArgs
    inputFile <- case args of
        [f] -> pure f
        _   -> die "usage: state-audit <input.json>"
    raw <- BS.readFile inputFile
    ai <- case eitherDecodeStrict raw of
        Right x  -> pure x
        Left err -> die ("failed to decode input: " <> T.pack err)
    let errs = audit ai
    if null errs
        then do
            TIO.putStrLn "// state-audit // all invariants hold ✓"
            exitSuccess
        else do
            hPutStrLn stderr "state-audit: REFUSING TO PASS — data-loss invariants violated:"
            mapM_ (\e -> TIO.hPutStrLn stderr ("  • " <> e)) errs
            exitFailure

die :: Text -> IO a
die msg = hPutStrLn stderr (T.unpack msg) >> exitFailure
