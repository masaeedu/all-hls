#! /usr/bin/env nix-shell
#! nix-shell --keep GITHUB_TOKEN --keep NIX_SSL_CERT_FILE
#! nix-shell -p "haskellPackages.ghcWithPackages (p: [ p.text p.bytestring p.github p.pretty-simple p.vector p.regex-tdfa p.aeson p.aeson-pretty p.cryptohash-sha256 p.http-client p.http-client-tls p.http-conduit p.http-types p.base16 p.async ])"
#! nix-shell -i runhaskell

{-# LANGUAGE
    OverloadedStrings
  , QuasiQuotes
  , TupleSections
  , DeriveGeneric
  , DerivingStrategies
  , DeriveAnyClass
  , GeneralizedNewtypeDeriving
  , PackageImports
#-}

import Prelude hiding ( writeFile, putStrLn )

import GitHub
import System.Environment ( getEnv )

import Text.Pretty.Simple ( pPrint )

import Control.Arrow ( (&&&) )

import Control.Category ( (<<<), (>>>) )

import Data.List ( find )
import Data.Maybe ( mapMaybe )

import Data.Text ( Text, pack, unpack )
import Data.Text.IO ( putStrLn )

import Data.Map ( Map )
import qualified Data.Map as M

import Data.Vector ( Vector )
import qualified Data.Vector as V

import Data.Maybe ( maybeToList )

import Text.Regex.TDFA

import Data.Aeson ( ToJSON(..), ToJSONKey(..) )
import qualified Data.Aeson as J
import qualified Data.Aeson.Encode.Pretty as J

import GHC.Generics

import Data.ByteString.Internal ( packChars )
import qualified Data.ByteString as BS


import Data.ByteString.Lazy ( writeFile )
import qualified Data.ByteString.Lazy as LBS

import Crypto.Hash.SHA256 ( hash )
import qualified Crypto.Hash.SHA256 as H

import Control.Applicative ( liftA2 )

import Data.IORef

import Network.HTTP.Client
import Network.HTTP.Client.TLS
import Network.HTTP.Types

import "base16" Data.ByteString.Base16 ( encodeBase16 )

import Control.Concurrent.Async

data Platform = Linux | MacOS | Windows
  deriving stock    (Eq, Ord, Show, Generic)
  deriving anyclass (ToJSON)

instance ToJSONKey Platform
  where
  toJSONKey = J.genericToJSONKey J.defaultJSONKeyOptions

type Version = Text
type Hash = Text

data Ref = Ref { url :: URL, hash :: Hash }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (ToJSON)

data HLSRelease = HLSRelease { wrapper :: Ref, ghcs :: Map Version Ref }
  deriving stock    (Eq, Ord, Show, Generic)
  deriving anyclass (ToJSON)

type Result = Map Version (Map Platform HLSRelease)

main :: IO ()
main = do
  token <- getEnv "GITHUB_TOKEN"
  Right releases <- github (OAuth $ packChars token) $ releasesR "haskell" "haskell-language-server" 10
  result <- hlsReleases $ V.toList releases
  writeFile "/mnt/code/git/nix/repos/all-hls/sources.json" $ J.encodePretty' (J.defConfig { J.confIndent = J.Spaces 2 }) $ result

  where

  hlsReleases :: [Release] -> IO Result
  hlsReleases
    =   fmap (releaseTagName &&& (V.toList . releaseAssets))
    >>> M.fromList
    >>> traverse extractBins

  extractBins :: [ReleaseAsset] -> IO (Map Platform HLSRelease)
  extractBins assets = fmap M.fromList $ foldMap (fmap maybeToList . flip extractRefs assets) $ [Linux, MacOS, Windows]

  extractRefs :: Platform -> [ReleaseAsset] -> IO (Maybe (Platform, HLSRelease))
  extractRefs p assets = fmap (fmap (p, )) $ liftA2 (liftA2 HLSRelease) hlws (fmap pure hls)
    where
    platformName :: Platform -> Text
    platformName Linux = "Linux"
    platformName MacOS = "macOS"
    platformName Windows = "Windows"

    downloadAndHash :: URL -> IO Hash
    downloadAndHash (URL url) = encodeBase16 <$> do
      manager <- newManager tlsManagerSettings -- TODO: See if this should be shared
      request <- parseRequest $ unpack url
      withResponse request manager $ \response -> do
        let
          status = responseStatus response
          readChunk = responseBody response
        if not $ statusIsSuccessful status
          then fail $ "The url " <> show url <> " responded with the non-2xx status code: " <> show status
          else do
            ior <- newIORef H.init
            let
              step = do
                chunk <- readChunk
                if BS.null chunk
                  then H.finalize <$> readIORef ior
                  else modifyIORef' ior (flip H.update $ chunk) *> step
            step


    refOfAsset :: ReleaseAsset -> IO Ref
    refOfAsset asset = Ref url <$> downloadAndHash url
      where
      url = URL $ releaseAssetBrowserDownloadUrl $ asset

    hlwsName :: Text
    hlwsName = "haskell-language-server-wrapper-" <> platformName p <> ".gz"

    hlws :: IO (Maybe Ref)
    hlws = traverse refOfAsset $ find ((== hlwsName) . releaseAssetName) assets

    hlsName :: Text
    hlsName = "haskell-language-server-" <> platformName p <> "-([0-9]+\\.[0-9]+\\.[0-9]+)\\.gz"

    hls :: IO (Map Version Ref)
    hls = fmap (M.fromList . mapMaybe id) $ runConcurrently $ traverse (Concurrently . parseHLS) assets

    parseHLS :: ReleaseAsset -> IO (Maybe (Version, Ref))
    parseHLS asset = traverse sequenceA $ do
      AllTextSubmatches xs <- releaseAssetName asset =~~ hlsName
      let ghc = xs !! 1
      pure $ (ghc, refOfAsset asset)
