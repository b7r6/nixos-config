-- | Thin PureScript bindings over the WebExtension API (via webextension-polyfill).
-- | FFI funcs return JS Promises; we adapt them to Aff with Control.Promise.
module WebExt
  ( queryActiveTabUrl
  , setBadge
  , createContextMenu
  , onContextMenuClicked
  , onActionClicked
  , onQueueMessage
  , storageGet
  , storageSet
  , notify
  ) where

import Prelude

import Control.Promise (Promise, fromAff, toAffE)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (Aff)

-- ── active tab url ─────────────────────────────────────────────────────────
foreign import queryActiveTabUrlImpl
  :: (forall a. Maybe a) -> (String -> Maybe String) -> Effect (Promise (Maybe String))

queryActiveTabUrl :: Aff (Maybe String)
queryActiveTabUrl = toAffE (queryActiveTabUrlImpl Nothing Just)

-- ── toolbar badge ──────────────────────────────────────────────────────────
foreign import setBadgeImpl :: String -> String -> Effect (Promise Unit)

-- | setBadge text color
setBadge :: String -> String -> Aff Unit
setBadge t c = toAffE (setBadgeImpl t c)

-- ── context menu ───────────────────────────────────────────────────────────
foreign import createContextMenuImpl
  :: String -> String -> Array String -> Effect (Promise Unit)

createContextMenu :: String -> String -> Array String -> Aff Unit
createContextMenu i t cs = toAffE (createContextMenuImpl i t cs)

foreign import onContextMenuClickedImpl :: (String -> Effect Unit) -> Effect Unit

onContextMenuClicked :: (String -> Effect Unit) -> Effect Unit
onContextMenuClicked = onContextMenuClickedImpl

foreign import onActionClickedImpl :: (Unit -> Effect Unit) -> Effect Unit

onActionClicked :: Effect Unit -> Effect Unit
onActionClicked handler = onActionClickedImpl (\_ -> handler)

-- | Listen for queue requests from content scripts. The handler is an Aff that
-- | returns whether queuing succeeded; we adapt it to the Promise<Boolean> the
-- | JS listener replies with.
foreign import onQueueMessageImpl :: (String -> Effect (Promise Boolean)) -> Effect Unit

onQueueMessage :: (String -> Aff Boolean) -> Effect Unit
onQueueMessage handler = onQueueMessageImpl (\url -> fromAff (handler url))

-- ── storage ────────────────────────────────────────────────────────────────
foreign import storageGetImpl
  :: String -> (forall a. Maybe a) -> (String -> Maybe String) -> Effect (Promise (Maybe String))

storageGet :: String -> Aff (Maybe String)
storageGet k = toAffE (storageGetImpl k Nothing Just)

foreign import storageSetImpl :: String -> String -> Effect (Promise Unit)

storageSet :: String -> String -> Aff Unit
storageSet k v = toAffE (storageSetImpl k v)

-- ── notifications ──────────────────────────────────────────────────────────
foreign import notifyImpl :: String -> String -> Effect (Promise String)

notify :: String -> String -> Aff Unit
notify t m = void (toAffE (notifyImpl t m))
