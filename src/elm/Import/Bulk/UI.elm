port module Import.Bulk.UI exposing (Model, Msg, init, subscriptions, update, view)

import Doc.Data as Data
import Doc.Metadata as Metadata exposing (Metadata)
import File exposing (File)
import File.Select as Select
import GlobalData exposing (GlobalData)
import Html exposing (..)
import Html.Attributes exposing (checked, classList, disabled, for, height, href, id, src, style, target, type_, width)
import Html.Events exposing (on, onCheck, onClick)
import Import.Bulk
import Json.Decode as Dec
import Json.Encode as Enc
import Octicons as Icon exposing (defaultOptions)
import Outgoing exposing (Msg(..), send)
import Session exposing (Session)
import SharedUI exposing (modalWrapper)
import Task
import Time
import Translation exposing (Language)
import Types exposing (Tree)



-- MODEL


type alias Model =
    { state : ImportModalState
    , user : Session
    , globalData : GlobalData.GlobalData
    }


type ImportModalState
    = Closed
    | ModalOpen { loginState : LoginState, isFileDragging : Bool }
    | ImportSelecting ImportSelection
    | ImportSaving ImportSelection


type LoginState
    = Checking
    | LoggedIn
    | LoggedOut
    | Manual


type alias ImportSelection =
    List
        { selected : Bool
        , tree : ( String, Metadata, Tree )
        }


init : GlobalData -> Session -> Model
init globalData user =
    { state = ModalOpen { loginState = Checking, isFileDragging = False }, user = user, globalData = globalData }



-- UPDATE


type Msg
    = NoOp
    | ModalClosed
    | LegacyLoginStateChanged Bool
    | ManualChosen
    | Retry
    | FileRequested
    | FileDraggedOver Bool
    | FileSelected File
    | FileLoaded Int String
    | SelectAllToggled Bool
    | TreeSelected String Bool
    | SelectionDone
    | Completed


update : Msg -> Model -> ( Model, Cmd Msg )
update msg ({ state, user } as model) =
    case ( msg, state ) of
        ( ModalClosed, _ ) ->
            ( { model | state = Closed }, Cmd.none )

        ( LegacyLoginStateChanged isLoggedIn, _ ) ->
            let
                newState =
                    if isLoggedIn then
                        LoggedIn

                    else
                        LoggedOut
            in
            ( { model | state = ModalOpen { loginState = newState, isFileDragging = False } }, Cmd.none )

        ( ManualChosen, _ ) ->
            ( { model | state = ModalOpen { loginState = Manual, isFileDragging = False } }, Cmd.none )

        ( Retry, ModalOpen modalData ) ->
            ( { model | state = ModalOpen { modalData | loginState = Checking } }, Cmd.none )

        ( FileRequested, _ ) ->
            ( model, Select.file [ "text/*", "application/json" ] FileSelected )

        ( FileDraggedOver isDraggedOver, ModalOpen modalState ) ->
            ( { model | state = ModalOpen { modalState | isFileDragging = isDraggedOver } }, Cmd.none )

        ( FileSelected file, _ ) ->
            ( model, Task.perform (FileLoaded (GlobalData.currentTime model.globalData |> Time.posixToMillis)) (File.toString file) )

        ( FileLoaded currTime contents, ModalOpen _ ) ->
            case Dec.decodeString (Import.Bulk.decoder currTime) contents of
                Ok dataList ->
                    let
                        listWithSelectState =
                            dataList
                                |> List.sortBy (\( _, mdata, _ ) -> Metadata.getUpdatedAt mdata |> Time.posixToMillis)
                                |> List.reverse
                                |> List.map (\t -> { selected = False, tree = t })
                    in
                    ( { model | state = ImportSelecting listWithSelectState }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        ( SelectAllToggled selectAll, ImportSelecting selectList ) ->
            let
                mapFn item =
                    { item | selected = selectAll }
            in
            ( { model | state = ImportSelecting (selectList |> List.map mapFn) }, Cmd.none )

        ( TreeSelected treeId isSelected, ImportSelecting selectList ) ->
            let
                mapFn ({ selected, tree } as orig) =
                    let
                        ( tid, _, _ ) =
                            tree
                    in
                    if tid == treeId then
                        { orig | selected = isSelected }

                    else
                        orig

                newList =
                    selectList |> List.map mapFn
            in
            ( { model | state = ImportSelecting newList }, Cmd.none )

        ( SelectionDone, ImportSelecting selectList ) ->
            let
                author =
                    user |> Session.name |> Maybe.withDefault "jane.doe@gmail.com"

                treeInfoToCommitReq ( id, mdata, tree ) =
                    Data.requestCommit tree author Data.empty (Metadata.encode mdata)

                treesToSave =
                    selectList
                        |> List.filter .selected
                        |> List.map .tree
                        |> List.map treeInfoToCommitReq
                        |> List.filterMap identity
                        |> Enc.list identity
            in
            ( { model | state = ImportSaving selectList }, send <| SaveBulkImportedData treesToSave )

        ( Completed, ImportSaving _ ) ->
            ( { model | state = Closed }, Cmd.none )

        _ ->
            ( model, Cmd.none )



-- VIEW


view : Language -> Model -> List (Html Msg)
view lang { state } =
    let
        fileDropDecoder =
            Dec.map
                (\files ->
                    case List.head files of
                        Just file ->
                            FileSelected file

                        Nothing ->
                            NoOp
                )
                (Dec.field "dataTransfer" (Dec.field "files" (Dec.list File.decoder)))
    in
    case state of
        Closed ->
            [ text "" ]

        ModalOpen { loginState, isFileDragging } ->
            case loginState of
                Checking ->
                    [ text "Checking to see if you're logged in or not..."
                    , br [] []
                    , iframe [ src "https://gingkoapp.com/loggedin", width 0, height 0 ] []
                    , br [] []
                    , p []
                        [ h4 [] [ text "Taking too long?" ]
                        , text "Click "
                        , button [ onClick ManualChosen ] [ text "here" ]
                        , text " to download your v1 files manually."
                        ]
                    ]
                        |> modalWrapper ModalClosed Nothing Nothing "Import From Gingko v1"

                LoggedIn ->
                    [ p [] [ text "To transfer multiple trees from your old account to this new one, follow these steps." ]
                    , p []
                        [ text "1. Click here to download a backup of all your trees: "
                        , br [] []
                        , a [ href "https://gingkoapp.com/export/all" ] [ text "Download Full Backup" ]
                        ]
                    , p []
                        [ text "2. Drag the backup file here:"
                        , div
                            [ classList [ ( "file-drop-zone", True ), ( "dragged-over", isFileDragging ) ]
                            , on "dragenter" (Dec.succeed (FileDraggedOver True))
                            , on "dragleave" (Dec.succeed (FileDraggedOver False))
                            , on "drop" fileDropDecoder
                            ]
                            []
                        , text "or find the file in your system: "
                        , button [ onClick FileRequested ] [ text "Browse..." ]
                        ]
                    ]
                        |> modalWrapper ModalClosed Nothing Nothing "Import From Gingko v1"

                LoggedOut ->
                    [ p [] [ text "To transfer trees from your old account, you need to be logged in to it." ]
                    , p [] [ text "But it seems you are not logged in to your old account." ]
                    , p []
                        [ text "1. "
                        , a [ href "https://gingkoapp.com/login", target "_blank" ] [ text "Login there" ]
                        , text "."
                        ]
                    , p []
                        [ text "2. Then, come back and ", button [ id "retry-button", onClick Retry ] [ text "Try again" ], text "." ]
                    , br [] []
                    , p []
                        [ h4 [] [ text "Having issues?" ]
                        , text "Click "
                        , button [ onClick ManualChosen ] [ text "here" ]
                        , text " to download your v1 files manually."
                        ]
                    ]
                        |> modalWrapper ModalClosed Nothing Nothing "Import From Gingko v1"

                Manual ->
                    [ p []
                        [ text "1. "
                        , a [ href "https://gingkoapp.com/login", target "_blank" ] [ text "Login" ]
                        , text " to your old Gingko App account."
                        ]
                    , p []
                        [ text "2. Click on the Settings (", Icon.gear defaultOptions, text ") icon." ]
                    , p []
                        [ text "3. Click 'Backup All Files'." ]
                    , p []
                        [ text "4. Drag the backup file here:"
                        , div
                            [ classList [ ( "file-drop-zone", True ), ( "dragged-over", isFileDragging ) ]
                            , on "dragenter" (Dec.succeed (FileDraggedOver True))
                            , on "dragleave" (Dec.succeed (FileDraggedOver False))
                            , on "drop" fileDropDecoder
                            ]
                            []
                        , text "or find the file in your system: "
                        , button [ onClick FileRequested ] [ text "Browse..." ]
                        ]
                    ]
                        |> modalWrapper ModalClosed Nothing Nothing "Import From Gingko v1"

        ImportSelecting importSelection ->
            let
                isDisabled =
                    importSelection
                        |> List.any .selected
                        |> not
            in
            [ div [ style "display" "flex", style "margin-top" "10px" ] [ span [ style "flex" "auto" ] [ text "Name" ], span [] [ text "Last Modified" ] ]
            , div [ id "import-selection-list" ] [ ul [] (List.map (viewSelectionEntry lang) importSelection) ]
            , span []
                [ input [ id "import-select-all", type_ "checkbox", onCheck <| SelectAllToggled ] []
                , label [ for "import-select-all" ] [ text "Select All" ]
                ]
            , button [ onClick SelectionDone, disabled isDisabled ] [ text "Import Selected Trees" ]
            ]
                |> modalWrapper ModalClosed Nothing Nothing "Import From Gingko v1"

        ImportSaving importSelection ->
            let
                importCount =
                    importSelection
                        |> List.filter .selected
                        |> List.length
            in
            [ p []
                [ text <| "Importing selected " ++ String.fromInt importCount ++ " trees..."
                , br [] []
                , text "This might take a while..."
                ]
            ]
                |> modalWrapper ModalClosed Nothing Nothing "Import From Gingko v1"


viewSelectionEntry : Language -> { selected : Bool, tree : ( String, Metadata, Tree ) } -> Html Msg
viewSelectionEntry lang { selected, tree } =
    let
        ( id, mdata, _ ) =
            tree
    in
    li []
        [ span []
            [ input [ type_ "checkbox", checked selected, onCheck (TreeSelected id) ] []
            , text (Metadata.getDocName mdata |> Maybe.withDefault "Untitled")
            ]
        , span [] [ text (Metadata.getUpdatedAt mdata |> Translation.dateFormat lang) ]
        ]



-- SUBSCRIPTIONS


port iframeLoginStateChange : (Bool -> msg) -> Sub msg


subscriptions : Model -> Sub Msg
subscriptions _ =
    iframeLoginStateChange LegacyLoginStateChanged
