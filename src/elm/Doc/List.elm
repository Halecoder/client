port module Doc.List exposing (Model, fetch, init, subscribe, update, viewLarge, viewSmall)

import Date
import Dict
import Doc.Metadata as Metadata exposing (Metadata)
import Html exposing (Html, a, div, h1, li, text, ul)
import Html.Attributes exposing (class, classList, href, title)
import Html.Events exposing (onClick, stopPropagationOn)
import Http exposing (Expect, expectStringResponse)
import Json.Decode as Dec
import Octicons as Icon
import Outgoing exposing (Msg(..), send)
import Route
import Session exposing (Session)
import Strftime
import Time
import Translation exposing (TranslationId(..), timeDistInWords, tr)



-- MODEL


type Model
    = Loading
    | SuccessLocal Time.Posix (List Metadata)
    | Success (Maybe Time.Posix) (List Metadata)
    | Failure Http.Error


init : Model
init =
    Loading


fetch : Session -> (Model -> msg) -> Cmd msg
fetch session msg =
    case Session.userDb session of
        Just userDb ->
            Cmd.batch
                [ send <| GetDocumentList userDb
                , Http.riskyRequest
                    { url = "/db/" ++ userDb ++ "/_design/testDocList/_view/docList"
                    , method = "GET"
                    , body = Http.emptyBody
                    , expect = expectJson msg
                    , headers = []
                    , timeout = Nothing
                    , tracker = Nothing
                    }
                ]

        Nothing ->
            Cmd.none



-- UPDATE


update : Model -> Model -> Model
update new old =
    let
        comp tsOld_ tsNew_ =
            Maybe.map2 (<=)
                (Maybe.map Time.posixToMillis tsOld_)
                (Maybe.map Time.posixToMillis tsNew_)
    in
    case ( old, new ) of
        ( SuccessLocal _ _, Success ts data ) ->
            Success ts data

        ( Success ts data, SuccessLocal _ _ ) ->
            Success ts data

        ( SuccessLocal tsOld dataOld, SuccessLocal tsNew dataNew ) ->
            if Time.posixToMillis tsOld <= Time.posixToMillis tsNew then
                SuccessLocal tsOld dataOld

            else
                SuccessLocal tsNew dataNew

        ( Success tsOld_ dataOld, Success tsNew_ dataNew ) ->
            case comp tsOld_ tsNew_ of
                Just False ->
                    Success tsOld_ dataOld

                _ ->
                    Success tsNew_ dataNew

        ( _, SuccessLocal ts data ) ->
            SuccessLocal ts data

        ( _, Success ts data ) ->
            Success ts data

        ( SuccessLocal ts data, Failure _ ) ->
            SuccessLocal ts data

        _ ->
            new



-- VIEW


type alias ListMsgs msg =
    { openDoc : String -> msg
    , deleteDoc : String -> msg
    }


viewLarge : ListMsgs msg -> Translation.Language -> Time.Posix -> Model -> Html msg
viewLarge msgs lang currTime model =
    case model of
        Loading ->
            h1 [] [ text "LOADING" ]

        SuccessLocal _ docList ->
            viewDocListLoaded msgs lang currTime docList

        Success _ docList ->
            viewDocListLoaded msgs lang currTime docList

        Failure err ->
            text <| "error!"


viewDocListLoaded : ListMsgs msg -> Translation.Language -> Time.Posix -> List Metadata -> Html msg
viewDocListLoaded msgs lang currTime docList =
    div [ classList [ ( "document-list", True ) ] ]
        (docList
            |> List.sortBy (Time.posixToMillis << Metadata.getUpdatedAt)
            |> List.reverse
            |> List.map (viewDocumentItem msgs lang currTime)
        )


viewDocumentItem : ListMsgs msg -> Translation.Language -> Time.Posix -> Metadata -> Html msg
viewDocumentItem msgs lang currTime metadata =
    let
        docId =
            Metadata.getDocId metadata

        docName_ =
            Metadata.getDocName metadata

        onClickThis msg =
            stopPropagationOn "click" (Dec.succeed ( msg, True ))

        -- TODO: fix timezone
        currDate =
            Date.fromPosix Time.utc currTime

        updatedTime =
            Metadata.getUpdatedAt metadata

        -- TODO: fix timezone
        updatedDate =
            Date.fromPosix Time.utc updatedTime

        -- TODO: fix timezone
        updatedString =
            updatedTime
                |> Strftime.format "%Y-%m-%d, %H:%M" Time.utc

        relativeString =
            timeDistInWords
                lang
                updatedTime
                currTime

        ( titleString, dateString ) =
            if Date.diff Date.Days updatedDate currDate <= 2 then
                ( updatedString, relativeString )

            else
                ( relativeString, updatedString )

        buttons =
            [ div
                [ onClickThis (msgs.deleteDoc docId), title <| tr lang DeleteDocument ]
                [ Icon.x Icon.defaultOptions ]
            ]
    in
    div
        [ class "document-item", onClick (msgs.openDoc docId) ]
        [ div [ class "doc-title" ] [ text (docName_ |> Maybe.withDefault "Untitled") ]
        , div [ class "doc-opened", title titleString ] [ text dateString ]
        , div [ class "doc-buttons" ] buttons
        ]


viewSmall : Metadata -> Model -> Html msg
viewSmall currentDocument model =
    let
        viewDocItem d =
            li [ classList [ ( "sidebar-document-item", True ), ( "active", d == currentDocument ) ] ]
                [ a [ href <| Route.toString (Route.DocUntitled (Metadata.getDocId d)) ]
                    [ Metadata.getDocName d |> Maybe.withDefault "Untitled" |> text ]
                ]
    in
    case model of
        Loading ->
            text "Loading..."

        SuccessLocal _ docs ->
            ul [ class "sidebar-document-list" ] (List.map viewDocItem docs)

        Success _ docs ->
            ul [ class "sidebar-document-list" ] (List.map viewDocItem docs)

        Failure _ ->
            text "Failed to load documents list."



-- DECODERS


decoderLocal : Dec.Value -> Model
decoderLocal json =
    let
        timestampDecoder =
            Dec.field "timestamp" Dec.int |> Dec.map Time.millisToPosix

        decoderWithTimestamp =
            Dec.map2 Tuple.pair
                Metadata.listDecoder
                timestampDecoder
    in
    case Dec.decodeValue decoderWithTimestamp json of
        Ok ( val, time ) ->
            SuccessLocal time val

        Err err ->
            Failure (Http.BadBody (Dec.errorToString err))


fromResult : Result Http.Error ( List Metadata, Maybe Time.Posix ) -> Model
fromResult result =
    case result of
        Err e ->
            Failure e

        Ok ( x, timestamp_ ) ->
            Success timestamp_ x


expectJson : (Model -> msg) -> Expect msg
expectJson toMsg =
    expectStringResponse (fromResult >> toMsg) <|
        \response ->
            case response of
                Http.BadUrl_ url ->
                    Err (Http.BadUrl url)

                Http.Timeout_ ->
                    Err Http.Timeout

                Http.NetworkError_ ->
                    Err Http.NetworkError

                Http.BadStatus_ metadata body ->
                    Err (Http.BadStatus metadata.statusCode)

                Http.GoodStatus_ metadata body ->
                    case Dec.decodeString Metadata.listDecoder body of
                        Ok value ->
                            let
                                timestamp_ : Maybe Time.Posix
                                timestamp_ =
                                    metadata.headers
                                        |> Dict.get "x-timestamp"
                                        |> Maybe.andThen String.toInt
                                        |> Maybe.map Time.millisToPosix
                            in
                            Ok ( value, timestamp_ )

                        Err err ->
                            Err (Http.BadBody (Dec.errorToString err))



-- SUBSCRIPTIONS


port documentListChanged : (Dec.Value -> msg) -> Sub msg


subscribe : (Model -> msg) -> Sub msg
subscribe msg =
    documentListChanged (decoderLocal >> msg)
