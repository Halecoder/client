module Page.Login exposing (Model, Msg, globalData, init, navKey, subscriptions, toUser, update, view)

import Ant.Icons.Svg as AntIcons
import Browser.Dom
import Browser.Navigation as Nav
import GlobalData exposing (GlobalData)
import Html exposing (..)
import Html.Attributes exposing (autocomplete, autofocus, class, for, href, id, placeholder, src, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Html.Extra exposing (viewIf)
import Http exposing (Error(..))
import Result exposing (Result)
import Route
import Session exposing (Session)
import Svg.Attributes
import Task
import Utils exposing (getFieldErrors)
import Validate exposing (Valid, Validator, ifBlank, ifInvalidEmail, ifTrue, validate)



-- MODEL


type alias Model =
    { globalData : GlobalData
    , session : Session
    , navKey : Nav.Key
    , email : String
    , password : String
    , showPassword : Bool
    , errors : List ( Field, String )
    }


type Field
    = Form
    | Email
    | Password


init : Nav.Key -> GlobalData -> Session -> ( Model, Cmd msg )
init nKey gData session =
    ( { globalData = gData
      , session = session
      , navKey = nKey
      , email = ""
      , password = ""
      , showPassword = False
      , errors = []
      }
    , Cmd.none
    )


toUser : Model -> Session
toUser model =
    model.session


navKey : Model -> Nav.Key
navKey model =
    model.navKey


globalData : Model -> GlobalData
globalData model =
    model.globalData



-- UPDATE


type Msg
    = NoOp
    | SubmittedForm
    | EnteredEmail String
    | EnteredPassword String
    | ToggleShowPassword
    | CompletedLogin (Result Http.Error Session)
    | GotUser Session


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        SubmittedForm ->
            case validate modelValidator model of
                Ok validModel ->
                    ( model
                    , sendLoginRequest validModel
                    )

                Err errs ->
                    ( { model | errors = errs }, Cmd.none )

        EnteredEmail email ->
            ( { model | email = email }, Cmd.none )

        EnteredPassword password ->
            ( { model | password = password }, Cmd.none )

        ToggleShowPassword ->
            ( { model | showPassword = not model.showPassword }, Task.attempt (\_ -> NoOp) (Browser.Dom.focus "password-input") )

        CompletedLogin (Ok user) ->
            ( { model | session = user }, Session.storeLogin user )

        CompletedLogin (Err error) ->
            let
                fallbackMsg =
                    ( Form, "Server Issue. Something wrong on our end. Please let us know!" )

                errorMsg =
                    case error of
                        Timeout ->
                            ( Form, "Timed out. Maybe there's a server issue?" )

                        NetworkError ->
                            ( Form, "Network Error. Maybe you're offline?" )

                        BadStatus statusCode ->
                            case statusCode of
                                401 ->
                                    ( Form, "Email or Password was incorrect.\n\nNOTE: that this is separate from existing gingkoapp.com accounts.\n\n" )

                                _ ->
                                    fallbackMsg

                        _ ->
                            fallbackMsg
            in
            ( { model | errors = [ errorMsg ], password = "" }, Cmd.none )

        GotUser user ->
            ( model, Route.pushUrl model.navKey Route.Root )


modelValidator : Validator ( Field, String ) Model
modelValidator =
    Validate.all
        [ Validate.firstError
            [ ifBlank .email ( Email, "Please enter an email address." )
            , ifInvalidEmail .email (\_ -> ( Email, "This does not seem to be a valid email." ))
            ]
        , ifTrue (\model -> String.length model.password < 7) ( Password, "Password should be 7 characters or more." )
        , ifBlank .password ( Password, "Please enter a password." )
        ]


sendLoginRequest : Valid Model -> Cmd Msg
sendLoginRequest validModel =
    let
        { email, password, session } =
            Validate.fromValid validModel
    in
    Session.requestLogin CompletedLogin email password session



-- VIEW


view : Model -> Html Msg
view model =
    let
        formErrors =
            getFieldErrors Form model.errors

        emailErrors =
            getFieldErrors Email model.errors

        passwordErrors =
            getFieldErrors Password model.errors

        fromLegacy =
            Session.fromLegacy model.session

        showHidePassword =
            if model.showPassword then
                div [ id "show-hide-password", onClick ToggleShowPassword ] [ AntIcons.eyeInvisibleOutlined [ Svg.Attributes.class "icon" ], text "Hide" ]

            else
                div [ id "show-hide-password", onClick ToggleShowPassword ] [ AntIcons.eyeOutlined [ Svg.Attributes.class "icon" ], text "Show" ]
    in
    div [ id "form-page" ]
        [ div [ class "page-backdrop" ] []
        , div [ class "page-bg" ] []
        , a [ class "brand", href "{%HOMEPAGE_URL%}" ] [ img [ id "logo", src "gingko-leaf-logo.svg" ] [] ]
        , div [ class "form-header-container" ]
            [ h1 [ class "headline" ] [ text "Login" ]
            , p [ class "subtitle" ] [ text "Welcome back!" ]
            ]
        , div [ class "center-form" ]
            [ form [ onSubmit SubmittedForm ]
                [ label [ for "email-input" ] [ text "Email" ]
                , input
                    [ onInput EnteredEmail
                    , id "email-input"
                    , type_ "email"
                    , value model.email
                    , autofocus True
                    , autocomplete True
                    ]
                    []
                , viewIf (not <| List.isEmpty emailErrors) <| div [ class "input-errors" ] [ text (String.join "\n" emailErrors) ]
                , label [ for "password-input" ] [ text "Password", showHidePassword ]
                , input
                    [ onInput EnteredPassword
                    , id "password-input"
                    , type_
                        (if model.showPassword then
                            "text"

                         else
                            "password"
                        )
                    , value model.password
                    , autocomplete True
                    ]
                    []
                , viewIf (not <| List.isEmpty passwordErrors) <| div [ class "input-errors" ] [ text (String.join "\n" passwordErrors) ]
                , if List.length formErrors > 0 then
                    div [ id "form-errors" ] [ text (String.join "\n" formErrors) ]

                  else
                    text ""
                , button [ id "login-button", class "cta" ] [ text "Login" ]
                , div [ id "post-cta-divider" ] [ hr [] [], div [] [ text "or" ], hr [] [] ]
                , span [ class "alt-action" ]
                    [ text "New to Gingko? "
                    , a [ href "/signup" ] [ text "Signup" ]
                    , br [] []
                    , br [] []
                    , a [ class "forgot-password", href "/forgot-password" ] [ text "Forgot your Password?" ]
                    ]
                , br [] []
                , if fromLegacy then
                    small [ class "extra-info", class "legacy" ]
                        [ text "This is "
                        , strong [] [ text "not connected" ]
                        , text " to your gingkoapp.com account."
                        , br [] []
                        , br [] []
                        , a [ href <| Route.toString Route.Signup ] [ text "Signup here" ]
                        , text " to get started."
                        ]

                  else
                    text ""
                ]
            ]
        ]



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Session.loginChanges GotUser
