-- | MV3 service worker entry. Wires:
-- |   - toolbar action click  -> queue the ACTIVE TAB url
-- |   - context-menu "Queue to media server" -> queue the clicked link/page url
-- | and gives toolbar-badge + notification feedback.
module Background (main) where

import Prelude

import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Queue (QueueResult(..), queueUrl)
import Queue.Config (loadConfig)
import WebExt
  ( createContextMenu
  , notify
  , onActionClicked
  , onContextMenuClicked
  , onQueueMessage
  , queryActiveTabUrl
  , setBadge
  )

menuId :: String
menuId = "queuedrop-queue"

main :: Effect Unit
main = do
  -- register the context menu (on links + page) at SW startup
  launchAff_ (createContextMenu menuId "Queue to media server" [ "link", "page" ])

  -- toolbar icon click -> queue the active tab
  onActionClicked do
    launchAff_ do
      murl <- queryActiveTabUrl
      case murl of
        Nothing -> feedback (Failed "no active tab url")
        Just url -> handle url

  -- context-menu click -> queue the provided url
  onContextMenuClicked \url ->
    launchAff_ (handle url)

  -- content-script button -> queue, replying with success boolean
  onQueueMessage \url -> do
    cfg <- loadConfig
    result <- queueUrl cfg url
    feedback result
    pure case result of
      Queued _ -> true
      Failed _ -> false

handle :: String -> Aff Unit
handle url = do
  cfg <- loadConfig
  result <- queueUrl cfg url
  feedback result

feedback :: QueueResult -> Aff Unit
feedback = case _ of
  Queued title -> do
    setBadge "ok" "#2e7d32"
    notify "Queued" ("Queued: " <> title)
  Failed err -> do
    setBadge "err" "#c62828"
    notify "Queue failed" err
