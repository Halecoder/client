module Page.Signup exposing (Model, Msg, globalData, init, navKey, subscriptions, toSession, update, view)

import Ant.Icons.Svg as AntIcons
import Browser.Dom
import Browser.Navigation as Nav
import GlobalData exposing (GlobalData)
import Html exposing (..)
import Html.Attributes exposing (autocomplete, autofocus, checked, class, classList, for, href, id, src, style, type_, value)
import Html.Events exposing (onCheck, onClick, onInput, onSubmit)
import Html.Extra exposing (viewIf)
import Http exposing (Error(..))
import Import.Template as Template
import Route
import Session exposing (Guest, LoggedIn, Session(..))
import Svg.Attributes
import Task
import Translation exposing (Language)
import Utils exposing (getFieldErrors)
import Validate exposing (Valid, Validator, ifBlank, ifInvalidEmail, ifTrue, validate)



-- MODEL


type alias Model =
    { globalData : GlobalData
    , session : Guest
    , transition : Maybe LoggedIn
    , email : String
    , password : String
    , showPassword : Bool
    , didOptIn : Bool
    , errors : List ( Field, FieldError )
    , navKey : Nav.Key
    }


type Field
    = Form
    | Email
    | Password


init : Nav.Key -> GlobalData -> Guest -> ( Model, Cmd Msg )
init nKey gData session =
    ( { globalData = gData
      , session = session
      , transition = Nothing
      , email = ""
      , password = ""
      , showPassword = False
      , didOptIn = False
      , errors = []
      , navKey = nKey
      }
    , Task.attempt (\_ -> NoOp) <| Browser.Dom.focus "signup-email"
    )


toSession : Model -> Session
toSession { session } =
    session |> GuestSession


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
    | ToggledOptIn Bool
    | CompletedSignup (Result Http.Error ( LoggedIn, Language ))
    | GotUser LoggedIn


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        SubmittedForm ->
            case validate modelValidator model of
                Ok validModel ->
                    ( model
                    , sendSignupRequest validModel
                    )

                Err errs ->
                    ( { model | errors = errs }, Cmd.none )

        EnteredEmail email ->
            ( { model | email = email }, Cmd.none )

        EnteredPassword password ->
            ( { model | password = password }, Cmd.none )

        ToggleShowPassword ->
            ( { model | showPassword = not model.showPassword }, Task.attempt (\_ -> NoOp) (Browser.Dom.focus "signup-password") )

        ToggledOptIn isOptedIn ->
            ( { model | didOptIn = isOptedIn }, Cmd.none )

        CompletedSignup (Ok ( user, lang )) ->
            ( { model | transition = Just user }, Session.storeSignup lang user )

        CompletedSignup (Err error) ->
            let
                fallbackMsg =
                    ( Form, ServerIssue )

                errorMsg =
                    case error of
                        Timeout ->
                            ( Form, TimeoutError )

                        NetworkError ->
                            ( Form, NetworkErrorMsg )

                        BadStatus statusCode ->
                            case statusCode of
                                409 ->
                                    ( Form, UsernameExists )

                                _ ->
                                    fallbackMsg

                        _ ->
                            fallbackMsg
            in
            ( { model | errors = [ errorMsg ], password = "" }, Cmd.none )

        GotUser _ ->
            -- If I want to route to different welcome trees, based on e.g. isMac or language, here is where I can.
            ( model, Route.replaceUrl model.navKey (Route.Import Template.WelcomeTree) )


emailValidator : Validator ( Field, FieldError ) Model
emailValidator =
    Validate.firstError
        [ ifBlank .email ( Email, BlankEmail )
        , ifInvalidEmail .email (\eml -> ( Email, InvalidEmail eml ))
        ]


passwordValidator : Validator ( Field, FieldError ) Model
passwordValidator =
    Validate.firstError
        [ ifBlank .password ( Password, BlankPassword )
        , ifTrue (\model -> String.length model.password < 7) ( Password, InvalidPassword )
        ]


modelValidator : Validator ( Field, FieldError ) Model
modelValidator =
    Validate.all
        [ emailValidator
        , passwordValidator
        ]


sendSignupRequest : Valid Model -> Cmd Msg
sendSignupRequest validModel =
    let
        { email, password, session, didOptIn } =
            Validate.fromValid validModel
    in
    Session.requestSignup CompletedSignup email password didOptIn session



-- VIEW


view : Model -> Html Msg
view model =
    let
        emailErrors =
            getFieldErrors Email model.errors

        passwordErrors =
            getFieldErrors Password model.errors

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
            [ h1 [ class "headline" ] [ text "Signup to Gingko Writer" ]
            , p [ class "subtitle" ] [ text "Write the way you think, organize as you go, and let your words flow." ]
            ]
        , div [ class "center-form" ]
            [ form [ onSubmit SubmittedForm ]
                [ label [ for "singup-email" ] [ text "Email" ]
                , input
                    [ id "signup-email"
                    , classList [ ( "has-error", List.length emailErrors > 0 ) ]
                    , onInput EnteredEmail
                    , type_ "email"
                    , value model.email
                    , autofocus True
                    , autocomplete True
                    ]
                    []
                , viewErrors Email model.errors
                , label [ for "singup-password" ] [ text "Password (7+ characters)", showHidePassword ]
                , input
                    [ id "signup-password"
                    , onInput EnteredPassword
                    , type_
                        (if model.showPassword then
                            "text"

                         else
                            "password"
                        )
                    , classList [ ( "has-error", List.length passwordErrors > 0 ) ]
                    , value model.password
                    , autocomplete True
                    ]
                    []
                , viewErrors Password model.errors
                , div [ style "display" "flex", style "gap" "6px" ]
                    [ input [ type_ "checkbox", id "email-optin", checked model.didOptIn, onCheck ToggledOptIn ] []
                    , label [ for "email-optin" ] [ text "Email me help & tips (~6 emails)", br [] [], text "and product news (every ~2 months)." ]
                    ]
                , viewErrors Form model.errors
                , button [ id "signup-button", class "cta" ] [ text "Start Writing" ]
                , div [ id "post-cta-divider" ] [ hr [] [], div [] [ text "or" ], hr [] [] ]
                , span [ class "alt-action" ] [ text "Already have an account? ", a [ href "/login" ] [ text "Login" ] ]
                ]
            ]
        ]


type FieldError
    = ServerIssue
    | TimeoutError
    | NetworkErrorMsg
    | UsernameExists
    | BlankEmail
    | InvalidEmail String
    | BlankPassword
    | InvalidPassword


viewErrors : Field -> List ( Field, FieldError ) -> Html msg
viewErrors field errors =
    case field of
        Form ->
            let
                formErrors =
                    getFieldErrors Form errors
            in
            viewIf (not <| List.isEmpty formErrors) (div [ id "form-errors" ] (List.map (viewError field) formErrors))

        Email ->
            let
                emailErrors =
                    getFieldErrors Email errors
            in
            viewIf (not <| List.isEmpty emailErrors) (div [ class "input-errors" ] (List.map (viewError field) emailErrors))

        Password ->
            let
                passwordErrors =
                    getFieldErrors Password errors
            in
            viewIf (not <| List.isEmpty passwordErrors) (div [ class "input-errors" ] (List.map (viewError field) passwordErrors))


viewError : Field -> FieldError -> Html msg
viewError field error =
    case ( field, error ) of
        ( Form, ServerIssue ) ->
            text "Server Issue. Something wrong on our end. Please let us know!"

        ( Form, TimeoutError ) ->
            text "Timed out. Maybe there's a server issue?"

        ( Form, NetworkErrorMsg ) ->
            text "Network error. Maybe you're offline?"

        ( Form, UsernameExists ) ->
            span [] [ text "Username already exists. ", a [ href "/login" ] [ text "Login" ], text "?" ]

        ( Email, BlankEmail ) ->
            text "Please enter an email address."

        ( Email, InvalidEmail eml ) ->
            text (eml ++ " does not seem to be a valid email.")

        ( Password, BlankPassword ) ->
            text "Please enter a password."

        ( Password, InvalidPassword ) ->
            text "Passwords should have 7 characters or more."

        _ ->
            text ""



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Session.userLoggedIn GotUser
