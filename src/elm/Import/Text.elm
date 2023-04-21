module Import.Text exposing (Model, Msg, Settings, init, setFileList, toTree, update, view)

import Doc.TreeStructure as TreeStructure exposing (defaultTree, labelTree, renameNodes)
import File exposing (File)
import File.Select
import Html exposing (Html, button, div, h3, hr, input, label, li, ol, text, ul)
import Html.Attributes exposing (checked, class, disabled, for, id, style, type_, value)
import Html.Events exposing (on, onClick, onInput)
import Html.Extra exposing (viewIf)
import List.Extra as ListExtra
import Random
import RandomId
import Regex
import SharedUI exposing (modalWrapper)
import Types exposing (Children(..), Tree)



-- MODEL


type alias Model =
    { files : List File
    , importSettings : Settings
    , field : String
    }


type Settings
    = NoSplit
    | SplitByParagraph
    | SplitBy String


init : Model
init =
    { files = [], importSettings = SplitByParagraph, field = "---" }



-- UPDATE


type Msg
    = FilesRequested
    | GotFiles File (List File)
    | SetNoSplit
    | SetSplitByParagraph
    | SetSplitBy
    | SepFieldChanged String
    | RequestImport


update : Msg -> Model -> { model : Model, cmd : Cmd Msg, sendTestHack : Bool, importRequested : Maybe ( List File, Settings ) }
update msg model =
    case msg of
        FilesRequested ->
            { model = model
            , cmd = File.Select.files [ ".md", ".markdown", ".mdown", "text/markdown", "text/x-markdown", "text/plain" ] GotFiles
            , sendTestHack = True
            , importRequested = Nothing
            }

        GotFiles head rest ->
            { model = { model | files = head :: rest }
            , cmd = Cmd.none
            , sendTestHack = False
            , importRequested = Nothing
            }

        SetNoSplit ->
            { model = { model | importSettings = NoSplit }, cmd = Cmd.none, sendTestHack = False, importRequested = Nothing }

        SetSplitByParagraph ->
            { model = { model | importSettings = SplitByParagraph }, cmd = Cmd.none, sendTestHack = False, importRequested = Nothing }

        SetSplitBy ->
            { model = { model | importSettings = SplitBy model.field }, cmd = Cmd.none, sendTestHack = False, importRequested = Nothing }

        SepFieldChanged sepString ->
            { model = { model | field = sepString, importSettings = SplitBy sepString }
            , cmd = Cmd.none
            , sendTestHack = False
            , importRequested = Nothing
            }

        RequestImport ->
            { model = model, cmd = Cmd.none, sendTestHack = False, importRequested = Just ( model.files, model.importSettings ) }


setFileList : List File -> Model -> Model
setFileList files model =
    { model | files = files }



-- VIEW


view : { closeMsg : msg, tagger : Msg -> msg } -> Model -> List (Html msg)
view msgs { files, importSettings, field } =
    let
        viewFile f =
            li [ class "file-item" ] [ text <| File.name f ]
    in
    [ h3 [] [ text "File Selection" ]
    , button [ id "import-text-file-input", onClick (msgs.tagger FilesRequested), style "height" "48px" ] [ text "Browse Files" ]
    , viewIf (not <| List.isEmpty files) <| ol [] (files |> List.map viewFile)
    , h3 [ style "margin-top" "32px" ] [ text "Splitting Options" ]
    , div [ id "splitting-options-list" ]
        [ div []
            [ input [ type_ "radio", id "split-by-paragraph", checked (importSettings == SplitByParagraph), onClick (msgs.tagger SetSplitByParagraph) ] []
            , label [ for "split-by-paragraph" ] [ text "Split By Paragraph and Blank Lines" ]
            ]
        , div []
            [ input [ id "split-by-separator", type_ "radio", checked (not (importSettings == NoSplit || importSettings == SplitByParagraph)), onClick (msgs.tagger SetSplitBy) ] []
            , label [ for "split-by-separator" ]
                [ text "Split by Separator : "
                , input
                    [ id "separator-input"
                    , onInput (msgs.tagger << SepFieldChanged)
                    , value field
                    ]
                    []
                ]
            ]
        , div []
            [ input [ type_ "radio", id "no-splitting", checked (importSettings == NoSplit), onClick (msgs.tagger SetNoSplit) ] []
            , label [ for "no-splitting" ] [ text "No Splitting (one card per file)" ]
            ]
        ]
    , button
        [ id "import-text-perform"
        , disabled (List.isEmpty files)
        , onClick (msgs.tagger RequestImport)
        , style "margin-top" "32px"
        , style "height" "48px"
        ]
        [ text "Import" ]
    ]
        |> modalWrapper msgs.closeMsg (Just "import-text-modal") (Just [ ( "import-text-modal-container", True ) ]) "Import Text Files"


toTree : Random.Seed -> List String -> List String -> Settings -> ( Tree, Random.Seed, Maybe String )
toTree seed metadata markdownStrings settings =
    let
        ( salt, newSeed ) =
            Random.step (RandomId.stringGenerator 7) seed

        maybeRemoveExtension str =
            Regex.fromString "\\..*$"
                |> Maybe.map (\rgx -> Regex.replace rgx (always "") str)
                |> Maybe.withDefault str

        splitter str =
            case settings of
                NoSplit ->
                    [ str ]

                SplitByParagraph ->
                    String.split "\n\n" str

                SplitBy sepString ->
                    String.split sepString str

        filenameAndSplitContent =
            ListExtra.zip metadata markdownStrings
                |> List.map (\( title, content ) -> ( maybeRemoveExtension title, splitter content ))

        mapOne idx content =
            Tree (String.fromInt (idx + 1))
                (String.trim content)
                (Children [])

        mapMultiple idx ( title, content ) =
            Tree (String.fromInt (idx + 1))
                ("# " ++ title)
                (Children (content |> List.indexedMap mapOne))
                |> labelTree idx (String.fromInt (idx + 1))
                |> renameNodes salt

        ( newTree, newTitle_ ) =
            case filenameAndSplitContent of
                ( title, contents ) :: [] ->
                    ( Tree "0" "" (Children (contents |> List.indexedMap mapOne))
                        |> labelTree 0 (String.fromInt 1)
                        |> renameNodes salt
                    , Just title
                    )

                [] ->
                    ( defaultTree, Nothing )

                multiple ->
                    ( Tree "0" "" (Children (multiple |> List.indexedMap mapMultiple)), Nothing )
    in
    ( newTree, newSeed, newTitle_ )
