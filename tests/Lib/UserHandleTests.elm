module Lib.UserHandleTests exposing (..)

import Expect
import Lib.UserHandle as UserHandle
import Test exposing (..)


fromString : Test
fromString =
    describe "UserHandle.fromString"
        [ test "Creates a UserHandle from an @ prefixed string" <|
            \_ ->
                let
                    handle =
                        UserHandle.fromString "@tolkien"

                    result =
                        handle |> Maybe.map UserHandle.toString
                in
                Expect.equal (Just "@tolkien") result
        , test "Fails to create from a non @ unprefixed string" <|
            \_ ->
                let
                    handle =
                        UserHandle.fromString "tolkien"
                in
                Expect.equal Nothing handle
        ]


fromUnprefixedString : Test
fromUnprefixedString =
    describe "UserHandle.fromUnprefixedString"
        [ test "Creates a UserHandle from an @unprefixed string" <|
            \_ ->
                let
                    handle =
                        UserHandle.fromUnprefixedString "tolkien"

                    result =
                        handle |> Maybe.map UserHandle.toString
                in
                Expect.equal (Just "@tolkien") result
        , test "Fails to create from a @ prefixed string" <|
            \_ ->
                let
                    handle =
                        UserHandle.fromUnprefixedString "@tolkien"
                in
                Expect.equal Nothing handle
        ]


equals : Test
equals =
    describe "UserHandle.equals"
        [ test "Returns True when the handles are the same" <|
            \_ ->
                let
                    a =
                        UserHandle.fromString "@tolkien"

                    b =
                        UserHandle.fromString "@tolkien"

                    result =
                        Maybe.map2 UserHandle.equals a b
                            |> Maybe.withDefault False
                in
                Expect.true "Expected handles @tolkien and @tolkien to be equal" result
        , test "Returns False when the handles are different" <|
            \_ ->
                let
                    a =
                        UserHandle.fromString "@gimli"

                    b =
                        UserHandle.fromString "@legolas"

                    result =
                        Maybe.map2 UserHandle.equals a b
                            |> Maybe.withDefault False
                in
                Expect.false "Expected handles @gimli and @legolas not to be equal" result
        ]


toString : Test
toString =
    describe "UserHandle.toString"
        [ test "Returns a string version of a UserHandle" <|
            \_ ->
                let
                    result =
                        "@gandalf"
                            |> UserHandle.fromString
                            |> Maybe.map UserHandle.toString
                            |> Maybe.withDefault "FAIL"
                in
                Expect.equal "@gandalf" result
        ]


toUnprefixedString : Test
toUnprefixedString =
    describe "UserHandle.toUnprefixedString"
        [ test "Returns a string version of a UserHandle without the @" <|
            \_ ->
                let
                    result =
                        "@aragorn"
                            |> UserHandle.fromString
                            |> Maybe.map UserHandle.toUnprefixedString
                            |> Maybe.withDefault "FAIL"
                in
                Expect.equal "aragorn" result
        ]


isValidHandle : Test
isValidHandle =
    describe "UserHandle.isValidHandle"
        [ test "Can be alphanumeric characters" <|
            \_ ->
                let
                    result =
                        UserHandle.isValidHandle "samwise123"
                in
                Expect.true "Expected alphanumeric characters in handles to succeed validation" result
        , test "Can include hyphens" <|
            \_ ->
                let
                    result =
                        UserHandle.isValidHandle "can-have-hyphens"
                in
                Expect.true "Expected hyphens in handles to succeed validation" result
        , test "Can' include consecutive hyphens" <|
            \_ ->
                let
                    result =
                        UserHandle.isValidHandle "cant-have----consecutive--hyphens"
                in
                Expect.false "Expected consecutive hyphens in handles to fail validation" result
        , test "Can't have spaces" <|
            \_ ->
                let
                    result =
                        UserHandle.isValidHandle "cant have spaces"
                in
                Expect.false "Expected spaces in handles to fail validation" result
        , test "Can't have symbols" <|
            \_ ->
                let
                    result =
                        UserHandle.isValidHandle "cant have $ymbols$!@#_"
                in
                Expect.false "Expected symbols in handles to fail validation" result
        , test "Can't have underscores" <|
            \_ ->
                let
                    result =
                        UserHandle.isValidHandle "cant_have_underscores"
                in
                Expect.false "Expected underscores in handles to fail validation" result
        , test "Can't be longer than 39 characters" <|
            \_ ->
                let
                    result =
                        UserHandle.isValidHandle "cantbemorethanthirtyninecharacterslongthatswaytolongofahandle"
                in
                Expect.false "Expected long handles to fail validation" result
        , test "Can't start with an @ symbol" <|
            \_ ->
                let
                    result =
                        UserHandle.isValidHandle "@rawhandlecantstartwithat"
                in
                Expect.false "Expected @ prefixed handles to fail validation" result
        , test "Can't start with a hyphen" <|
            \_ ->
                let
                    result =
                        UserHandle.isValidHandle "-cant-start-with-a-hyphen"
                in
                Expect.false "Expected - prefixed handles to fail validation" result
        , test "Can't end with a hyphen" <|
            \_ ->
                let
                    result =
                        UserHandle.isValidHandle "can-end-with-a-hyphen-"
                in
                Expect.false "Expected - suffixed handles to fail validation" result
        ]



{- -}
