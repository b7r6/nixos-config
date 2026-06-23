-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                            // hypermodern // supabase // secret generator
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--   "The thing about a key is that if it works, nobody cares how it was cut."
--
-- Generate the Supabase secret bundle and encrypt it with agenix. The bash
-- version proved fragile twice in one session:
--   1. subshell-under-pipefail → empty .age file → whole stack credential-less
--   2. JWT minting via openssl|tr|dgst — correct but unauditable
--
-- This version: `jose` for JWT (correct by construction), `entropy`/`crypton`
-- for random, `shelly` for the one agenix call with explicit stdin. The failure
-- modes that bit us are structurally eliminated.

module Main (main) where

import           Crypto.Hash            (SHA256 (..))
import           Crypto.MAC.HMAC        (HMAC (..), hmac)
import           Data.ByteArray         (convert)
import qualified Data.ByteString        as BS
import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Char8  as C8
import           Data.Text              (Text)
import qualified Data.Text              as T
import qualified Data.Text.Encoding     as TE
import qualified Data.Text.IO           as TIO
import           Data.Time.Clock.POSIX  (getPOSIXTime)
import           Data.Word              (Word8)
import           Numeric                (showHex)
import           Shelly
import           System.Entropy         (getEntropy)
import           System.Environment     (getArgs)
import           System.Exit            (exitFailure)
import           System.IO              (hPutStrLn, stderr)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                                  // crypto
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- | URL-safe base64 without padding (JWT segments).
b64url :: BS.ByteString -> BS.ByteString
b64url = C8.filter (/= '=') . C8.map f . B64.encode
  where
    f '+' = '-'
    f '/' = '_'
    f c   = c

{- | Mint an HS256 JWT. Uses crypton's HMAC directly — correct, auditable, no
shelling out to openssl.
-}
mintHS256 :: BS.ByteString -> BS.ByteString -> BS.ByteString
mintHS256 secret payload =
    let hdr = b64url "{\"alg\":\"HS256\",\"typ\":\"JWT\"}"
        pl = b64url payload
        signing = hdr <> "." <> pl
        sig = b64url (convert (hmac secret signing :: HMAC SHA256))
     in signing <> "." <> sig

-- | Generate n random bytes as a hex string (2n chars).
randHex :: Int -> IO BS.ByteString
randHex n = toHex <$> getEntropy n
  where
    toHex = C8.pack . concatMap word8Hex . BS.unpack
    word8Hex :: Word8 -> String
    word8Hex w = let s = showHex w "" in if length s == 1 then '0' : s else s

-- | Generate n random bytes as base64.
randB64 :: Int -> IO BS.ByteString
randB64 n = B64.encode <$> getEntropy n

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                                     // main
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

main :: IO ()
main = do
    args <- getArgs
    let dest = case args of (d : _) -> d; _ -> "agenix/machines/supabase-env.age"

    -- TODO: check file doesn't already exist

    -- Generate key material
    now <- round <$> getPOSIXTime :: IO Int
    let iat = now
        expiry = iat + 3650 * 24 * 3600 -- ~10y
    jwtSecret <- randHex 32
    postgresPass <- randHex 24
    secretKeyBase <- randB64 48
    vaultEncKey <- randHex 16
    pgMetaCryptoKey <- randB64 24
    dashboardPass <- randHex 16

    let anonPayload = "{\"role\":\"anon\",\"iss\":\"supabase\",\"iat\":" <> C8.pack (show iat) <> ",\"exp\":" <> C8.pack (show expiry) <> "}"
        svcPayload = "{\"role\":\"service_role\",\"iss\":\"supabase\",\"iat\":" <> C8.pack (show iat) <> ",\"exp\":" <> C8.pack (show expiry) <> "}"
        anonKey = mintHS256 jwtSecret anonPayload
        svcRoleKey = mintHS256 jwtSecret svcPayload

    let bundle =
            C8.unlines
                [ "POSTGRES_PASSWORD=" <> postgresPass
                , "JWT_SECRET=" <> jwtSecret
                , "ANON_KEY=" <> anonKey
                , "SERVICE_ROLE_KEY=" <> svcRoleKey
                , "SECRET_KEY_BASE=" <> secretKeyBase
                , "VAULT_ENC_KEY=" <> vaultEncKey
                , "PG_META_CRYPTO_KEY=" <> pgMetaCryptoKey
                , "DASHBOARD_USERNAME=supabase"
                , "DASHBOARD_PASSWORD=" <> dashboardPass
                ]

    -- Feed the bundle to agenix via stdin (Shelly). No subshell, no pipe — Shelly
    -- writes stdin explicitly, so the empty-pipe failure mode cannot recur.
    shelly $ do
        setStdin (TE.decodeUtf8 bundle)
        run_ "agenix" ["-e", T.pack dest]

    -- Guard: verify the file is non-empty (belt-and-suspenders).
    size <- BS.length <$> BS.readFile dest
    if size == 0
        then die "encrypted file is empty — agenix did not receive stdin"
        else do
            TIO.putStrLn ("wrote " <> T.pack dest)
            TIO.putStrLn ("dashboard login: supabase / " <> TE.decodeUtf8 dashboardPass)

die :: Text -> IO a
die msg = hPutStrLn stderr (T.unpack msg) >> exitFailure
