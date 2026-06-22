-- | Content script: inject a floating "Queue" button. The button's click is
-- | handled in Content.js (it messages the background SW), so the PS side here
-- | is just the injection trigger at document load.
module Content (main) where

import Prelude
import Effect (Effect)

foreign import injectButtonImpl :: String -> Effect Unit

main :: Effect Unit
main = injectButtonImpl "⬇ Queue"
