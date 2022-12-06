module Code.Definition.Math exposing (..)

import Html exposing (Html, button, div, input, node, text)
import Html.Attributes exposing (attribute, class, readonly, type_, value)
import UI
import UI.Icon as Icon

inlineMath : String -> Html msg
inlineMath math = 
  node "inline-math" 
    [ ]
    [ text "Hello World" ]

displayMath : String -> Html msg
displayMath math = 
  node "display-math" 
    [ ]
    [ text "Hello World" ]
