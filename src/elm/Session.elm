port module Session exposing (PaymentStatus(..), Session, confirmEmail, currentTime, daysLeft, db, decode, documents, fileMenuOpen, fromLegacy, getDocName, getMetadata, isMac, isNotConfirmed, language, lastDocId, loggedIn, loginChanges, logout, name, paymentStatus, requestForgotPassword, requestLogin, requestResetPassword, requestSignup, seed, setFileOpen, setLanguage, setSeed, setShortcutTrayOpen, setSortBy, shortcutTrayOpen, sortBy, storeLogin, storeSignup, sync, updateDocuments, updateTime, updateUpgrade, upgradeModel, userSettingsChange)

import Browser.Navigation as Nav
import Coders exposing (sortByDecoder)
import Doc.List as DocList exposing (Model(..))
import Doc.Metadata as Metadata exposing (Metadata)
import Http
import Json.Decode as Dec exposing (Decoder)
import Json.Decode.Pipeline exposing (optional, optionalAt, required)
import Json.Encode as Enc
import List.Extra as ListExtra
import Outgoing exposing (Msg(..), send)
import Random
import Time exposing (Posix)
import Translation exposing (Language(..), langFromString, langToString, languageDecoder)
import Types exposing (SortBy(..))
import Upgrade
import Utils exposing (hexEncode)



-- MODEL


type Session
    = LoggedIn SessionData UserData
    | Guest SessionData GuestData


type alias SessionData =
    -- Not persisted
    { seed : Random.Seed
    , isMac : Bool
    , currentTime : Time.Posix
    , fileMenuOpen : Bool
    , lastDocId : Maybe String
    , fromLegacy : Bool
    }


type alias UserData =
    { email : String
    , language : Translation.Language
    , upgradeModel : Upgrade.Model
    , paymentStatus : PaymentStatus
    , confirmedAt : Maybe Time.Posix
    , shortcutTrayOpen : Bool
    , sortBy : SortBy
    , documents : DocList.Model
    }


type PaymentStatus
    = Trial Time.Posix
    | Customer String


type alias GuestData =
    -- Persisted in localStorage
    { language : Translation.Language
    }



-- GETTERS


getFromSession : (SessionData -> a) -> Session -> a
getFromSession getter session =
    case session of
        LoggedIn sessionData _ ->
            getter sessionData

        Guest sessionData _ ->
            getter sessionData


name : Session -> Maybe String
name session =
    case session of
        LoggedIn _ { email } ->
            Just email

        Guest _ _ ->
            Nothing


seed : Session -> Random.Seed
seed session =
    getFromSession .seed session


isMac : Session -> Bool
isMac session =
    getFromSession .isMac session


currentTime : Session -> Time.Posix
currentTime session =
    getFromSession .currentTime session


lastDocId : Session -> Maybe String
lastDocId session =
    getFromSession .lastDocId session


fromLegacy : Session -> Bool
fromLegacy session =
    getFromSession .fromLegacy session


db : Session -> Maybe String
db session =
    case session of
        LoggedIn _ { email } ->
            Just ("userdb-" ++ hexEncode email)

        Guest _ _ ->
            Nothing


fileMenuOpen : Session -> Bool
fileMenuOpen session =
    getFromSession .fileMenuOpen session


language : Session -> Language
language session =
    case session of
        LoggedIn _ data ->
            data.language

        Guest _ data ->
            data.language


upgradeModel : Session -> Maybe Upgrade.Model
upgradeModel session =
    case session of
        LoggedIn _ data ->
            Just data.upgradeModel

        Guest _ _ ->
            Nothing


paymentStatus : Session -> PaymentStatus
paymentStatus session =
    case session of
        LoggedIn _ data ->
            data.paymentStatus

        Guest _ _ ->
            Trial (currentTime session |> add14days)


add14days : Posix -> Posix
add14days time =
    Time.posixToMillis time
        |> (\ms -> 3600 * 24 * 1000 * 14 + ms |> Time.millisToPosix)


daysLeft : Session -> Maybe Int
daysLeft session =
    case paymentStatus session of
        Trial expiry ->
            ((Time.posixToMillis expiry - Time.posixToMillis (currentTime session)) |> toFloat)
                / (1000 * 3600 * 24)
                |> round
                |> Just

        Customer _ ->
            Nothing


isNotConfirmed : Session -> Bool
isNotConfirmed session =
    case session of
        LoggedIn _ data ->
            data.confirmedAt == Nothing

        Guest _ _ ->
            True


shortcutTrayOpen : Session -> Bool
shortcutTrayOpen session =
    case session of
        LoggedIn _ data ->
            data.shortcutTrayOpen

        Guest _ _ ->
            False


sortBy : Session -> SortBy
sortBy session =
    case session of
        LoggedIn _ data ->
            data.sortBy

        Guest _ _ ->
            ModifiedAt


documents : Session -> DocList.Model
documents session =
    case session of
        LoggedIn _ data ->
            data.documents

        Guest _ _ ->
            DocList.init


getMetadata : Session -> String -> Maybe Metadata
getMetadata session docId =
    case documents session of
        Success docList ->
            docList
                |> ListExtra.find (\d -> Metadata.getDocId d == docId)

        _ ->
            Nothing


getDocName : Session -> String -> Maybe String
getDocName session docId =
    getMetadata session docId
        |> Maybe.andThen Metadata.getDocName


loggedIn : Session -> Bool
loggedIn session =
    case session of
        LoggedIn _ _ ->
            True

        Guest _ _ ->
            False



-- UPDATE


sync : Dec.Value -> Session -> Session
sync json session =
    let
        settingsDecoder : Decoder { language : Language, paymentStatus : PaymentStatus, confirmedAt : Maybe Time.Posix }
        settingsDecoder =
            Dec.succeed (\lang payStat confAt -> { language = lang, paymentStatus = payStat, confirmedAt = confAt })
                |> optional "language" languageDecoder En
                |> optional "paymentStatus" decodePaymentStatus (Trial (currentTime session |> add14days))
                |> optional "confirmedAt" decodeConfirmedStatus (Just (Time.millisToPosix 0))
    in
    case ( Dec.decodeValue settingsDecoder json, session ) of
        ( Ok newSettings, LoggedIn sessData userData ) ->
            LoggedIn sessData
                { userData
                    | language = newSettings.language
                    , paymentStatus = newSettings.paymentStatus
                    , confirmedAt = newSettings.confirmedAt
                }

        ( Ok newSettings, Guest sessData guestData ) ->
            Guest sessData { guestData | language = newSettings.language }

        ( Err _, _ ) ->
            session


updateSession : (SessionData -> SessionData) -> Session -> Session
updateSession updateFn session =
    case session of
        LoggedIn sessionData data ->
            LoggedIn (updateFn sessionData) data

        Guest sessionData data ->
            Guest (updateFn sessionData) data


setSeed : Random.Seed -> Session -> Session
setSeed newSeed session =
    updateSession (\s -> { s | seed = newSeed }) session


updateTime : Time.Posix -> Session -> Session
updateTime newTime session =
    updateSession (\s -> { s | currentTime = newTime }) session


setFileOpen : Bool -> Session -> Session
setFileOpen isOpen session =
    updateSession (\s -> { s | fileMenuOpen = isOpen }) session


setLanguage : Language -> Session -> Session
setLanguage lang session =
    case session of
        LoggedIn key data ->
            LoggedIn key { data | language = lang }

        Guest key data ->
            Guest key { data | language = lang }


confirmEmail : Session -> Session
confirmEmail session =
    case session of
        LoggedIn key data ->
            LoggedIn key { data | confirmedAt = Just (currentTime session) }

        Guest _ _ ->
            session


setShortcutTrayOpen : Bool -> Session -> Session
setShortcutTrayOpen isOpen session =
    case session of
        LoggedIn key data ->
            LoggedIn key { data | shortcutTrayOpen = isOpen }

        Guest _ _ ->
            session


setSortBy : SortBy -> Session -> Session
setSortBy newSort session =
    case session of
        LoggedIn key data ->
            LoggedIn key { data | sortBy = newSort }

        Guest _ _ ->
            session


updateDocuments : DocList.Model -> Session -> Session
updateDocuments docList session =
    case session of
        LoggedIn sessionData data ->
            LoggedIn sessionData { data | documents = DocList.update data.sortBy docList data.documents }

        Guest _ _ ->
            session


updateUpgrade : Upgrade.Msg -> Session -> Session
updateUpgrade upgradeMsg session =
    case session of
        LoggedIn sessionData data ->
            LoggedIn sessionData { data | upgradeModel = Upgrade.update upgradeMsg data.upgradeModel }

        Guest _ _ ->
            session



-- ENCODER & DECODER


decode : Dec.Value -> Session
decode json =
    case Dec.decodeValue decoder json of
        Ok session ->
            session

        Err err ->
            let
                errToSeed =
                    err
                        |> Dec.errorToString
                        |> String.right 10
                        |> String.toList
                        |> List.map Char.toCode
                        |> List.foldl (+) 12345
                        |> Random.initialSeed
            in
            Guest
                { seed = errToSeed
                , isMac = False
                , currentTime = Time.millisToPosix 0
                , fileMenuOpen = False
                , lastDocId = Nothing
                , fromLegacy = False
                }
                (GuestData En)


decoder : Dec.Decoder Session
decoder =
    Dec.oneOf [ decodeLoggedIn, decodeGuest ]


decodeLoggedIn : Dec.Decoder Session
decodeLoggedIn =
    Dec.succeed
        (\email s os t legacy lang side payStat confirmTime trayOpen sortCriteria lastDoc ->
            let
                newPayStat =
                    if payStat == Trial (Time.millisToPosix 0) then
                        Trial (t |> add14days)

                    else
                        payStat
            in
            LoggedIn
                { seed = s
                , isMac = os
                , currentTime = t
                , fileMenuOpen = side
                , lastDocId = Nothing
                , fromLegacy = legacy
                }
                (UserData email lang Upgrade.init newPayStat confirmTime trayOpen sortCriteria DocList.init)
        )
        |> required "email" Dec.string
        |> required "seed" (Dec.int |> Dec.map Random.initialSeed)
        |> required "isMac" Dec.bool
        |> required "currentTime" (Dec.int |> Dec.map Time.millisToPosix)
        |> optional "fromLegacy" Dec.bool False
        |> optional "language" (Dec.string |> Dec.map langFromString) En
        |> optional "sidebarOpen" Dec.bool False
        |> optional "paymentStatus" decodePaymentStatus (Trial (Time.millisToPosix 0))
        |> optional "confirmedAt" decodeConfirmedStatus (Just (Time.millisToPosix 0))
        |> optional "shortcutTrayOpen" Dec.bool False
        |> optional "sortBy" sortByDecoder ModifiedAt
        |> optional "lastDocId" (Dec.maybe Dec.string) Nothing


decodeConfirmedStatus : Decoder (Maybe Time.Posix)
decodeConfirmedStatus =
    Dec.oneOf
        [ Dec.null Nothing
        , Dec.int |> Dec.map Time.millisToPosix |> Dec.maybe
        ]


decodePaymentStatus : Dec.Decoder PaymentStatus
decodePaymentStatus =
    Dec.oneOf
        [ Dec.succeed Customer |> required "customer" Dec.string
        , Dec.succeed Trial |> required "trialExpires" (Dec.int |> Dec.map Time.millisToPosix)
        ]


decodeGuest : Dec.Decoder Session
decodeGuest =
    Dec.succeed
        (\s os t legacy l side ->
            Guest
                { seed = s
                , isMac = os
                , currentTime = t
                , fileMenuOpen = side
                , lastDocId = Nothing
                , fromLegacy = legacy
                }
                (GuestData l)
        )
        |> required "seed" (Dec.int |> Dec.map Random.initialSeed)
        |> required "isMac" Dec.bool
        |> required "currentTime" (Dec.int |> Dec.map Time.millisToPosix)
        |> optional "fromLegacy" Dec.bool False
        |> optional "language" (Dec.string |> Dec.map langFromString) En
        |> optional "sidebarOpen" Dec.bool False


responseDecoder : Session -> Dec.Decoder Session
responseDecoder session =
    let
        builder email lang payStat checklist trayOpen sortCriteria =
            case session of
                Guest sessionData data ->
                    LoggedIn sessionData (UserData email lang Upgrade.init payStat checklist trayOpen sortCriteria DocList.init)

                LoggedIn _ _ ->
                    session
    in
    Dec.succeed builder
        |> required "email" Dec.string
        |> optionalAt [ "settings", "language" ] (Dec.map langFromString Dec.string) En
        |> optionalAt [ "settings", "paymentStatus" ] decodePaymentStatus (Trial (Time.millisToPosix 0))
        |> optionalAt [ "settings", "confirmedAt" ] decodeConfirmedStatus (Just (Time.millisToPosix 0))
        |> optionalAt [ "settings", "shortcutTrayOpen" ] Dec.bool False
        |> optionalAt [ "settings", "sortBy" ] sortByDecoder ModifiedAt


encode : Session -> Enc.Value
encode session =
    case session of
        LoggedIn _ data ->
            Enc.object
                [ ( "email", Enc.string data.email )
                , ( "language", data.language |> langToString |> Enc.string )
                ]

        Guest _ data ->
            Enc.object
                [ ( "language", data.language |> langToString |> Enc.string )
                ]



-- AUTHENTICATION


requestSignup : (Result Http.Error Session -> msg) -> String -> String -> Bool -> Session -> Cmd msg
requestSignup toMsg email password didOptIn session =
    let
        requestBody =
            Enc.object
                [ ( "email", Enc.string email )
                , ( "password", Enc.string password )
                , ( "subscribed", Enc.bool didOptIn )
                ]
                |> Http.jsonBody
    in
    Http.post
        { url = "/signup"
        , body = requestBody
        , expect = Http.expectJson toMsg (responseDecoder session)
        }


storeSignup : Session -> Cmd msg
storeSignup session =
    store (Just session)


requestLogin : (Result Http.Error Session -> msg) -> String -> String -> Session -> Cmd msg
requestLogin toMsg email password session =
    let
        requestBody =
            Enc.object
                [ ( "email", Enc.string email )
                , ( "password", Enc.string password )
                ]
                |> Http.jsonBody
    in
    Http.riskyRequest
        { method = "POST"
        , url = "/login"
        , headers = []
        , body = requestBody
        , expect = Http.expectJson toMsg (responseDecoder session)
        , timeout = Nothing
        , tracker = Nothing
        }


storeLogin : Session -> Cmd msg
storeLogin session =
    store (Just session)


requestForgotPassword : (Result Http.Error Session -> msg) -> String -> Session -> Cmd msg
requestForgotPassword toMsg email session =
    let
        requestBody =
            Enc.object
                [ ( "email", Enc.string email )
                ]
                |> Http.jsonBody
    in
    Http.post
        { url = "/forgot-password"
        , body = requestBody
        , expect = Http.expectJson toMsg (responseDecoder session)
        }


requestResetPassword : (Result Http.Error Session -> msg) -> { newPassword : String, token : String } -> Session -> Cmd msg
requestResetPassword toMsg { newPassword, token } session =
    let
        requestBody =
            Enc.object
                [ ( "token", Enc.string token )
                , ( "password", Enc.string newPassword )
                ]
                |> Http.jsonBody
    in
    Http.post
        { url = "/reset-password"
        , body = requestBody
        , expect = Http.expectJson toMsg (responseDecoder session)
        }


logout : Cmd msg
logout =
    store Nothing



-- PORTS


store : Maybe Session -> Cmd msg
store session_ =
    case session_ of
        Just session ->
            send <| StoreUser (encode session)

        Nothing ->
            send <| StoreUser Enc.null


loginChanges : (Session -> msg) -> Sub msg
loginChanges toMsg =
    userLoginChange (decode >> toMsg)


port userLoginChange : (Dec.Value -> msg) -> Sub msg


port userSettingsChange : (Dec.Value -> msg) -> Sub msg
