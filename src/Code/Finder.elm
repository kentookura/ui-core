module Code.Finder exposing (Model, Msg, OutMsg(..), init, isShowFinderKeyboardShortcut, update, view)

import Browser.Dom as Dom
import Code.CodebaseApi as CodebaseApi
import Code.Config exposing (Config)
import Code.Definition.AbilityConstructor exposing (AbilityConstructor(..))
import Code.Definition.Category as Category
import Code.Definition.DataConstructor exposing (DataConstructor(..))
import Code.Definition.Reference as Reference exposing (Reference(..))
import Code.Definition.Source as Source
import Code.Definition.Term exposing (Term(..))
import Code.Definition.Type exposing (Type(..))
import Code.Finder.FinderMatch as FinderMatch exposing (FinderMatch)
import Code.Finder.SearchOptions as SearchOptions exposing (SearchOptions(..), WithinOption(..))
import Code.FullyQualifiedName as FQN exposing (FQN)
import Code.HashQualified exposing (HashQualified(..))
import Code.Perspective as Perspective exposing (Perspective)
import Code.Syntax as Syntax
import Html
    exposing
        ( Html
        , a
        , div
        , h3
        , header
        , input
        , label
        , mark
        , p
        , section
        , span
        , table
        , tbody
        , td
        , text
        , tr
        )
import Html.Attributes
    exposing
        ( autocomplete
        , class
        , classList
        , id
        , placeholder
        , spellcheck
        , title
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Http
import Lib.HttpApi as HttpApi exposing (ApiRequest)
import Lib.OperatingSystem as OperatingSystem exposing (OperatingSystem)
import Lib.ScrollTo as ScrollTo
import Lib.SearchResults as SearchResults exposing (SearchResults(..))
import Lib.Util as Util
import List.Nonempty as NEL
import Maybe.Extra as MaybeE
import Task
import UI
import UI.Icon as Icon
import UI.KeyboardShortcut as KeyboardShortcut exposing (KeyboardShortcut(..))
import UI.KeyboardShortcut.Key as Key exposing (Key(..))
import UI.KeyboardShortcut.KeyboardEvent as KeyboardEvent exposing (KeyboardEvent)
import UI.Modal as Modal



-- MODEL


type FinderSearch
    = NotAsked
    | Searching String (Maybe FinderSearchResults)
    | Success String FinderSearchResults
    | Failure String Http.Error


type alias FinderSearchResults =
    SearchResults FinderMatch


type alias Model =
    { input : String
    , search : FinderSearch
    , keyboardShortcut : KeyboardShortcut.Model
    , options : SearchOptions
    }


init : Config -> SearchOptions -> ( Model, Cmd Msg )
init config options =
    ( { input = ""
      , search = NotAsked
      , keyboardShortcut = KeyboardShortcut.init config.operatingSystem
      , options = options
      }
    , focusSearchInput
    )



-- UPDATE


type Msg
    = NoOp
    | UpdateInput String
    | PerformSearch String
    | ResetOrClose
    | Close
    | Select Reference
    | Keydown KeyboardEvent
    | FetchMatchesFinished String (Result Http.Error (List FinderMatch))
    | RemoveWithinOption
    | KeyboardShortcutMsg KeyboardShortcut.Msg


type OutMsg
    = Remain
    | Exit
    | OpenDefinition Reference


update : Config -> Msg -> Model -> ( Model, Cmd Msg, OutMsg )
update config msg model =
    let
        debounceDelay =
            300

        exit =
            ( model, Cmd.none, Exit )

        reset =
            ( { model | input = "", search = NotAsked }, focusSearchInput, Remain )

        resetOrClose =
            if model.input == "" then
                exit

            else
                reset
    in
    case msg of
        NoOp ->
            ( model, Cmd.none, Remain )

        UpdateInput input ->
            let
                isSequenceShortcutInput =
                    String.contains ";" input

                isShowFinderShortcut =
                    input == "/"

                isValidInput =
                    not isSequenceShortcutInput && not isShowFinderShortcut
            in
            if String.isEmpty input then
                ( { model | input = input, search = NotAsked }, Cmd.none, Remain )

            else if String.length input > 1 && isValidInput then
                ( { model | input = input }, Util.delayMsg debounceDelay (PerformSearch input), Remain )

            else if isValidInput then
                ( { model | input = input }, Cmd.none, Remain )

            else
                ( model, Cmd.none, Remain )

        PerformSearch query ->
            if query == model.input then
                let
                    ( search, fetch ) =
                        performSearch config model.options model.search query
                in
                ( { model | search = search }, HttpApi.perform config.api fetch, Remain )

            else
                ( model, Cmd.none, Remain )

        Close ->
            exit

        FetchMatchesFinished query matches ->
            let
                search =
                    case matches of
                        Err e ->
                            Failure query e

                        Ok ms ->
                            Success query (SearchResults.fromList ms)
            in
            if query == model.input then
                ( { model | search = search }, Cmd.none, Remain )

            else
                ( model, Cmd.none, Remain )

        RemoveWithinOption ->
            let
                options =
                    SearchOptions.removeWithin config.perspective model.options

                -- Don't perform search when the query is empty.
                ( search, cmd ) =
                    if not (String.isEmpty model.input) then
                        let
                            ( search_, fetch ) =
                                performSearch config options model.search model.input
                        in
                        ( search_, HttpApi.perform config.api fetch )

                    else
                        ( model.search, Cmd.none )
            in
            ( { model | search = search, options = options }
            , cmd
            , Remain
            )

        ResetOrClose ->
            resetOrClose

        Select ref ->
            ( model, Cmd.none, OpenDefinition ref )

        Keydown event ->
            let
                ( keyboardShortcut, kCmd ) =
                    KeyboardShortcut.collect model.keyboardShortcut event.key

                cmd =
                    Cmd.map KeyboardShortcutMsg kCmd

                newModel =
                    { model | keyboardShortcut = keyboardShortcut }

                shortcut =
                    KeyboardShortcut.fromKeyboardEvent model.keyboardShortcut event
            in
            case shortcut of
                Sequence _ Escape ->
                    resetOrClose

                Sequence _ ArrowUp ->
                    let
                        newSearch =
                            finderSearchMap SearchResults.prev model.search

                        scrollToCmd =
                            newSearch
                                |> finderSearchToMaybe
                                |> Maybe.andThen SearchResults.focus
                                |> Maybe.map FinderMatch.reference
                                |> Maybe.map scrollToMatch
                                |> Maybe.withDefault Cmd.none
                    in
                    ( { newModel | search = newSearch }, Cmd.batch [ cmd, scrollToCmd ], Remain )

                Sequence _ ArrowDown ->
                    let
                        newSearch =
                            finderSearchMap SearchResults.next model.search

                        scrollToCmd =
                            newSearch
                                |> finderSearchToMaybe
                                |> Maybe.andThen SearchResults.focus
                                |> Maybe.map FinderMatch.reference
                                |> Maybe.map scrollToMatch
                                |> Maybe.withDefault Cmd.none
                    in
                    ( { newModel | search = newSearch }, Cmd.batch [ cmd, scrollToCmd ], Remain )

                Sequence _ Enter ->
                    let
                        openFocused results =
                            results
                                |> SearchResults.focus
                                |> Maybe.map FinderMatch.reference
                                |> MaybeE.unwrap Remain OpenDefinition

                        out =
                            case model.search of
                                Success _ r ->
                                    openFocused r

                                _ ->
                                    Remain
                    in
                    ( newModel, cmd, out )

                Sequence (Just Semicolon) k ->
                    case Key.toNumber k of
                        Just n ->
                            let
                                out =
                                    model.search
                                        |> finderSearchToMaybe
                                        |> Maybe.andThen (SearchResults.getAt (n - 1))
                                        |> Maybe.map FinderMatch.reference
                                        |> Maybe.map OpenDefinition
                                        |> Maybe.withDefault Remain
                            in
                            ( newModel, cmd, out )

                        Nothing ->
                            ( newModel, cmd, Remain )

                _ ->
                    ( newModel, cmd, Remain )

        KeyboardShortcutMsg kMsg ->
            let
                ( keyboardShortcut, cmd ) =
                    KeyboardShortcut.update kMsg model.keyboardShortcut
            in
            ( { model | keyboardShortcut = keyboardShortcut }, Cmd.map KeyboardShortcutMsg cmd, Remain )



-- Helpers


finderSearchMap : (FinderSearchResults -> FinderSearchResults) -> FinderSearch -> FinderSearch
finderSearchMap f finderSearch =
    case finderSearch of
        Success q r ->
            Success q (f r)

        _ ->
            finderSearch


finderSearchToMaybe : FinderSearch -> Maybe FinderSearchResults
finderSearchToMaybe fs =
    case fs of
        Success _ r ->
            Just r

        _ ->
            Nothing


isShowFinderKeyboardShortcut : OperatingSystem -> KeyboardShortcut -> Bool
isShowFinderKeyboardShortcut os shortcut =
    case shortcut of
        KeyboardShortcut.Chord Ctrl (K _) ->
            True

        KeyboardShortcut.Chord Meta (K _) ->
            os == OperatingSystem.MacOS

        Sequence _ ForwardSlash ->
            True

        _ ->
            False



-- EFFECTS


performSearch :
    Config
    -> SearchOptions
    -> FinderSearch
    -> String
    -> ( FinderSearch, ApiRequest (List FinderMatch) Msg )
performSearch { toApiEndpoint, perspective } options search query =
    let
        search_ =
            case search of
                Success _ r ->
                    Searching query (Just r)

                Searching _ (Just r) ->
                    Searching query (Just r)

                _ ->
                    Searching query Nothing

        fetch =
            case options of
                SearchOptions AllNamespaces ->
                    fetchMatches
                        toApiEndpoint
                        (Perspective.toRootPerspective perspective)
                        Nothing
                        query

                SearchOptions (WithinNamespacePerspective _) ->
                    fetchMatches toApiEndpoint
                        perspective
                        Nothing
                        query

                SearchOptions (WithinNamespace fqn) ->
                    fetchMatches
                        toApiEndpoint
                        perspective
                        (Just fqn)
                        query
    in
    ( search_, fetch )


fetchMatches : CodebaseApi.ToApiEndpoint -> Perspective -> Maybe FQN -> String -> ApiRequest (List FinderMatch) Msg
fetchMatches toApiEndpoint perspective withinFqn query =
    let
        limit =
            9

        sourceWidth =
            Syntax.Width 100
    in
    CodebaseApi.Find
        { perspective = perspective
        , withinFqn = withinFqn
        , limit = limit
        , sourceWidth = sourceWidth
        , query = query
        }
        |> toApiEndpoint
        |> HttpApi.toRequest FinderMatch.decodeMatches (FetchMatchesFinished query)


focusSearchInput : Cmd Msg
focusSearchInput =
    Task.attempt (always NoOp) (Dom.focus "search")


scrollToMatch : Reference -> Cmd Msg
scrollToMatch ref =
    let
        targetId =
            "match-" ++ Reference.toString ref
    in
    ScrollTo.scrollTo NoOp "finder-results" targetId



-- VIEW


indexToShortcut : Int -> Maybe Key
indexToShortcut index =
    let
        n =
            index + 1
    in
    if n > 9 then
        Nothing

    else
        n |> String.fromInt |> Key.fromString |> Just


viewMarkedNaming : FinderMatch.MatchPositions -> Maybe String -> FQN -> Html msg
viewMarkedNaming matchedPositions namespace name =
    let
        namespaceMod =
            namespace
                |> Maybe.map String.length
                |> Maybe.map ((+) 1)
                |> Maybe.withDefault 0

        mark_ mod i s =
            if NEL.member (i + mod) matchedPositions then
                mark [] [ text s ]

            else
                text s

        markedName =
            name
                |> FQN.toString
                |> String.toList
                |> List.map (List.singleton >> String.fromList)
                |> List.indexedMap (mark_ namespaceMod)

        markedNamespace =
            namespace
                |> Maybe.map String.toList
                |> Maybe.map (List.map (List.singleton >> String.fromList))
                |> Maybe.map (List.indexedMap (mark_ 0))
                |> Maybe.map (\ns -> span [ class "in" ] [ text "in" ] :: ns)
                |> Maybe.withDefault []
    in
    td
        [ class "naming" ]
        [ div [ class "name-and-namespace" ]
            [ label [ class "name" ] markedName
            , label [ class "namespace" ] markedNamespace
            ]
        ]


viewMatch : KeyboardShortcut.Model -> FinderMatch -> Bool -> Maybe Key -> Html Msg
viewMatch keyboardShortcut match isFocused shortcut =
    let
        shortcutIndicator =
            if isFocused then
                KeyboardShortcut.view keyboardShortcut (Sequence Nothing Key.Enter)

            else
                case shortcut of
                    Nothing ->
                        UI.nothing

                    Just key ->
                        KeyboardShortcut.view keyboardShortcut (Sequence (Just Key.Semicolon) key)

        matchId ref =
            "match-" ++ Reference.toString ref

        viewMatch_ reference icon naming source =
            tr
                [ id (matchId reference)
                , classList
                    [ ( "definition-match", True )
                    , ( "focused", isFocused )
                    ]
                , onClick (Select reference)
                ]
                [ td [ class "category" ] [ Icon.view icon ]
                , naming
                , td [ class "source" ] [ source ]
                , td [] [ div [ class "shortcut" ] [ shortcutIndicator ] ]
                ]
    in
    case match.item of
        FinderMatch.TypeItem (Type _ category { fqn, name, namespace, source }) ->
            viewMatch_
                (TypeReference (NameOnly fqn))
                (Category.icon (Category.Type category))
                (viewMarkedNaming match.matchPositions namespace name)
                (Source.viewTypeSource Source.Monochrome source)

        FinderMatch.TermItem (Term _ category { fqn, name, namespace, signature }) ->
            viewMatch_
                (TermReference (NameOnly fqn))
                (Category.icon (Category.Term category))
                (viewMarkedNaming match.matchPositions namespace name)
                (Source.viewTermSignature Source.Monochrome signature)

        FinderMatch.DataConstructorItem (DataConstructor _ { fqn, name, namespace, signature }) ->
            viewMatch_
                (DataConstructorReference (NameOnly fqn))
                Icon.dataConstructor
                (viewMarkedNaming match.matchPositions namespace name)
                (Source.viewTermSignature Source.Monochrome signature)

        FinderMatch.AbilityConstructorItem (AbilityConstructor _ { fqn, name, namespace, signature }) ->
            viewMatch_
                (AbilityConstructorReference (NameOnly fqn))
                Icon.abilityConstructor
                (viewMarkedNaming match.matchPositions namespace name)
                (Source.viewTermSignature Source.Monochrome signature)


viewMatches : KeyboardShortcut.Model -> SearchResults.Matches FinderMatch -> Html Msg
viewMatches keyboardShortcut matches =
    let
        matchItems =
            matches
                |> SearchResults.mapMatchesToList (\d f -> ( d, f ))
                |> List.indexedMap (\i ( d, f ) -> ( d, f, indexToShortcut i ))
                |> List.map (\( d, f, s ) -> viewMatch keyboardShortcut d f s)
    in
    section [ id "finder-results", class "results" ] [ table [] [ tbody [] matchItems ] ]


view : Model -> Html Msg
view model =
    let
        viewResults query res =
            case res of
                Empty ->
                    UI.emptyStateMessage ("No matching definitions found for \"" ++ query ++ "\"")

                SearchResults matches ->
                    viewMatches model.keyboardShortcut matches

        results =
            case model.search of
                Success q res ->
                    viewResults q res

                Searching q (Just res) ->
                    viewResults q res

                Failure query error ->
                    div [ class "error" ]
                        [ h3 [ title (Util.httpErrorToString error) ] [ Icon.view Icon.warn, text "Unable to search" ]
                        , p [] [ text ("Something went wrong trying to find \"" ++ query ++ "\"") ]
                        , p [] [ text "Please try again" ]
                        ]

                _ ->
                    UI.nothing

        isSearching =
            case model.search of
                Searching _ _ ->
                    True

                _ ->
                    False

        content =
            Modal.CustomContent
                (div
                    [ classList [ ( "is-searching", isSearching ) ] ]
                    [ SearchOptions.view RemoveWithinOption model.options
                    , header []
                        [ Icon.search |> Icon.withToggleAnimation isSearching |> Icon.view
                        , input
                            [ type_ "text"
                            , id "search"
                            , autocomplete False
                            , spellcheck False
                            , placeholder "Search by name and/or namespace"
                            , onInput UpdateInput
                            , value model.input
                            ]
                            []
                        , a [ class "reset", onClick ResetOrClose ] [ Icon.view Icon.x ]
                        ]
                    , results
                    ]
                )

        keyboardEvent =
            KeyboardEvent.on KeyboardEvent.Keydown Keydown
                |> KeyboardEvent.stopPropagation
                |> KeyboardEvent.preventDefaultWhen (\evt -> evt.key == ArrowUp || evt.key == ArrowDown)
                |> KeyboardEvent.attach
    in
    Modal.modal "finder" Close content
        -- We stopPropagation such that movement shortcuts, like J or K, for the
        -- workspace aren't triggered when in the modal when the use is trying to
        -- type those letters into the search field
        |> Modal.withAttributes [ keyboardEvent ]
        |> Modal.view
