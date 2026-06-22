-- | Options page: load endpoint/token from storage into the form, and save on
-- | click. Pairs with static/options.html (ids: endpoint, token, save, status).
module Options (main) where

import Prelude

import Data.Maybe (fromMaybe)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Queue (defaultEndpoint)
import WebExt (storageGet, storageSet)

foreign import getValueImpl :: String -> Effect String
foreign import setValueImpl :: String -> String -> Effect Unit
foreign import setTextImpl :: String -> String -> Effect Unit
foreign import onClickImpl :: String -> (Unit -> Effect Unit) -> Effect Unit

main :: Effect Unit
main = do
  -- populate the form from storage
  launchAff_ do
    ep <- storageGet "endpoint"
    tk <- storageGet "token"
    liftEffect (setValueImpl "endpoint" (fromMaybe defaultEndpoint ep))
    liftEffect (setValueImpl "token" (fromMaybe "" tk))

  -- save handler
  onClickImpl "save" \_ ->
    launchAff_ do
      ep <- liftEffect (getValueImpl "endpoint")
      tk <- liftEffect (getValueImpl "token")
      storageSet "endpoint" ep
      storageSet "token" tk
      liftEffect (setTextImpl "status" "Saved.")
