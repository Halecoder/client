module Doc.UI exposing (countWords, viewConflict, viewHeader, viewHistory, viewLoadingSpinner, viewMobileButtons, viewSaveIndicator, viewSearchField, viewShortcuts, viewSidebar, viewSidebarStatic, viewTemplateSelector, viewTooltip, viewVideo, viewWordCount)

import Ant.Icons.Svg as AntIcons
import Browser.Dom exposing (Element)
import Coders exposing (treeToMarkdownString)
import Diff exposing (..)
import Doc.Data as Data
import Doc.Data.Conflict as Conflict exposing (Conflict, Op(..), Selection(..), opString)
import Doc.List as DocList
import Doc.Metadata as Metadata exposing (Metadata)
import Doc.TreeStructure as TreeStructure exposing (defaultTree)
import Doc.TreeUtils as TreeUtils exposing (..)
import Html exposing (Html, a, br, button, del, div, fieldset, h1, h2, h3, h4, h5, hr, iframe, img, input, ins, label, li, option, pre, select, small, span, text, ul)
import Html.Attributes as A exposing (..)
import Html.Attributes.Extra exposing (attributeIf)
import Html.Events exposing (keyCode, on, onBlur, onCheck, onClick, onFocus, onInput, onMouseEnter, onMouseLeave, onSubmit, stopPropagationOn)
import Html.Events.Extra exposing (onChange)
import Html.Extra exposing (viewIf)
import Import.Template exposing (Template(..))
import Json.Decode as Dec
import List.Extra as ListExtra exposing (getAt)
import Octicons as Icon exposing (defaultOptions)
import Page.Doc.Export exposing (ExportFormat(..), ExportSelection(..))
import Page.Doc.Theme exposing (Theme(..))
import Regex exposing (Regex, replace)
import Route
import Session exposing (PaymentStatus(..), Session)
import SharedUI exposing (modalWrapper)
import Time exposing (posixToMillis)
import Translation exposing (Language(..), TranslationId(..), langFromString, langToString, languageName, timeDistInWords, tr)
import Types exposing (Children(..), CursorPosition(..), SidebarMenuState(..), SidebarState(..), TextCursorInfo, TooltipPosition(..), ViewMode(..), ViewState)



-- HEADER


viewHeader :
    { titleFocused : msg
    , titleFieldChanged : String -> msg
    , titleEdited : msg
    , titleEditCanceled : msg
    , tooltipRequested : String -> TooltipPosition -> String -> msg
    , tooltipClosed : msg
    , toggledExport : msg
    , exportSelectionChanged : ExportSelection -> msg
    , exportFormatChanged : ExportFormat -> msg
    , export : msg
    , printRequested : msg
    , toggledUpgradeModal : Bool -> msg
    }
    -> Maybe String
    ->
        { m
            | titleField : Maybe String
            , dropdownState : SidebarMenuState
            , exportPreview : Bool
            , exportSettings : ( ExportSelection, ExportFormat )
            , dirty : Bool
            , lastLocalSave : Maybe Time.Posix
            , lastRemoteSave : Maybe Time.Posix
            , session : Session
        }
    -> Html msg
viewHeader msgs title_ model =
    let
        language =
            Session.language model.session

        handleKeys =
            on "keyup"
                (Dec.andThen
                    (\int ->
                        case int of
                            27 ->
                                Dec.succeed msgs.titleEditCanceled

                            13 ->
                                Dec.succeed msgs.titleEdited

                            _ ->
                                Dec.fail "Ignore keyboard event"
                    )
                    keyCode
                )

        titleArea =
            let
                titleString =
                    model.titleField |> Maybe.withDefault "Untitled"
            in
            span [ id "title" ]
                [ div [ class "title-grow-wrap" ]
                    [ div [ class "shadow" ]
                        [ text <|
                            if titleString /= "" then
                                titleString

                            else
                                " "
                        ]
                    , input
                        [ id "title-rename"
                        , type_ "text"
                        , onInput msgs.titleFieldChanged
                        , onBlur msgs.titleEdited
                        , onFocus msgs.titleFocused
                        , handleKeys
                        , size 1
                        , value titleString
                        , attribute "data-private" "lipsum"
                        ]
                        []
                    ]
                , viewSaveIndicator language model (Session.currentTime model.session)
                ]

        isSelected expSel =
            (model.exportSettings |> Tuple.first) == expSel

        exportSelectionBtnAttributes expSel =
            [ onClick <| msgs.exportSelectionChanged expSel
            , classList [ ( "selected", isSelected expSel ) ]
            ]

        isFormat expFormat =
            (model.exportSettings |> Tuple.second) == expFormat

        exportFormatBtnAttributes expFormat =
            [ onClick <| msgs.exportFormatChanged expFormat
            , classList [ ( "selected", isFormat expFormat ) ]
            ]
    in
    div [ id "document-header" ]
        [ titleArea
        , div
            [ id "export-icon"
            , class "header-button"
            , classList [ ( "open", model.exportPreview ) ]
            , onClick msgs.toggledExport
            , onMouseEnter <| msgs.tooltipRequested "export-icon" BelowTooltip "Export or Print"
            , onMouseLeave msgs.tooltipClosed
            ]
            [ AntIcons.fileDoneOutlined [] ]
        , viewUpgradeButton
            msgs.toggledUpgradeModal
            model.session
        , viewIf model.exportPreview <|
            div [ id "export-menu" ]
                [ div [ id "export-selection", class "toggle-button" ]
                    [ div (exportSelectionBtnAttributes ExportEverything) [ text "Everything" ]
                    , div (exportSelectionBtnAttributes ExportSubtree) [ text "Current Subtree" ]
                    , div (exportSelectionBtnAttributes ExportCurrentColumn) [ text "Current Column" ]
                    ]
                , div [ id "export-format", class "toggle-button" ]
                    [ div (exportFormatBtnAttributes DOCX) [ text "Word" ]
                    , div (exportFormatBtnAttributes PlainText) [ text "Plain Text" ]
                    , div (exportFormatBtnAttributes JSON) [ text "JSON" ]
                    ]
                ]
        ]


viewSaveIndicator :
    Language
    -> { m | dirty : Bool, lastLocalSave : Maybe Time.Posix, lastRemoteSave : Maybe Time.Posix }
    -> Time.Posix
    -> Html msg
viewSaveIndicator language { dirty, lastLocalSave, lastRemoteSave } currentTime =
    let
        lastChangeString =
            timeDistInWords
                language
                (lastLocalSave |> Maybe.withDefault (Time.millisToPosix 0))
                currentTime

        saveStateSpan =
            if dirty then
                span [ title (tr language LastSaved ++ " " ++ lastChangeString) ] [ text <| tr language UnsavedChanges ]

            else
                case ( lastLocalSave, lastRemoteSave ) of
                    ( Nothing, Nothing ) ->
                        span [] [ text <| tr language NeverSaved ]

                    ( Just time, Nothing ) ->
                        if Time.posixToMillis time == 0 then
                            span [] [ text <| tr language NeverSaved ]

                        else
                            span [ title (tr language LastEdit ++ " " ++ lastChangeString) ] [ text <| tr language SavedInternally ]

                    ( Just commitTime, Just fileTime ) ->
                        if posixToMillis commitTime <= posixToMillis fileTime then
                            span [ title (tr language LastEdit ++ " " ++ lastChangeString) ]
                                [ text <| tr language ChangesSynced ]

                        else
                            span [ title (tr language LastEdit ++ " " ++ lastChangeString) ] [ text <| tr language SavedInternally ]

                    ( Nothing, Just _ ) ->
                        span [ title (tr language LastEdit ++ " " ++ lastChangeString) ] [ text <| tr language DatabaseError ]
    in
    div
        [ id "save-indicator", classList [ ( "inset", True ), ( "saving", dirty ) ] ]
        [ saveStateSpan
        ]


viewUpgradeButton :
    (Bool -> msg)
    -> Session
    -> Html msg
viewUpgradeButton toggledUpgradeModal session =
    let
        currentTime =
            Session.currentTime session

        lang =
            Session.language session

        upgradeButton =
            div [ id "upgrade-button", onClick <| toggledUpgradeModal True ] [ text "Upgrade" ]

        maybeUpgrade =
            case Session.paymentStatus session of
                Customer _ ->
                    text ""

                Trial expiry ->
                    let
                        daysLeft =
                            ((Time.posixToMillis expiry - Time.posixToMillis currentTime) |> toFloat)
                                / (1000 * 3600 * 24)
                                |> round

                        trialClass =
                            if daysLeft <= 7 && daysLeft > 5 then
                                "trial-light"

                            else if daysLeft <= 5 && daysLeft > 3 then
                                "trial-medium"

                            else
                                "trial-dark"
                    in
                    if daysLeft <= 7 then
                        upgradeButton

                    else
                        upgradeButton

                Unknown ->
                    upgradeButton
    in
    maybeUpgrade



-- SIDEBAR


type alias SidebarMsgs msg =
    { sidebarStateChanged : SidebarState -> msg
    , noOp : msg
    , clickedNew : msg
    , tooltipRequested : String -> TooltipPosition -> String -> msg
    , tooltipClosed : msg
    , clickedSwitcher : msg
    , clickedHelp : msg
    , toggledShortcuts : msg
    , clickedEmailSupport : msg
    , toggledAccount : msg
    , logout : msg
    , fileSearchChanged : String -> msg
    , contextMenuOpened : String -> ( Float, Float ) -> msg
    , exportPreviewToggled : Bool -> msg
    , exportSelectionChanged : ExportSelection -> msg
    , exportFormatChanged : ExportFormat -> msg
    , export : msg
    , importJSONRequested : msg
    , languageChanged : String -> msg
    , themeChanged : Theme -> msg
    , fullscreenRequested : msg
    }


viewSidebar : Language -> SidebarMsgs msg -> Metadata -> String -> DocList.Model -> String -> SidebarMenuState -> SidebarState -> Html msg
viewSidebar lang msgs currentDocument fileFilter docList accountEmail dropdownState sidebarState =
    let
        isOpen =
            not (sidebarState == SidebarClosed)

        helpOpen =
            dropdownState == Help

        accountOpen =
            dropdownState == Account

        toggle menu =
            if sidebarState == menu then
                msgs.sidebarStateChanged <| SidebarClosed

            else
                msgs.sidebarStateChanged <| menu

        viewIf cond v =
            if cond then
                v

            else
                text ""
    in
    div [ id "sidebar", onClick <| toggle File, classList [ ( "open", isOpen ) ] ]
        ([ div [ id "brand" ]
            ([ img [ src "../gingko-leaf-logo.svg", width 28 ] [] ]
                ++ (if isOpen then
                        [ h2 [ id "brand-name" ] [ text "Gingko Writer" ]
                        , div [ id "sidebar-collapse-icon" ] [ AntIcons.leftOutlined [] ]
                        ]

                    else
                        [ text "" ]
                   )
            )
         , div
            [ id "new-icon"
            , class "sidebar-button"
            , onClickStop msgs.clickedNew
            , onMouseEnter <| msgs.tooltipRequested "new-icon" RightTooltip "New Document"
            , onMouseLeave msgs.tooltipClosed
            ]
            [ AntIcons.fileOutlined [] ]
         , div
            [ id "documents-icon"
            , class "sidebar-button"
            , classList [ ( "open", isOpen ) ]
            , attributeIf (not isOpen) <| onMouseEnter <| msgs.tooltipRequested "documents-icon" RightTooltip "Show Document List"
            , attributeIf (not isOpen) <| onMouseLeave msgs.tooltipClosed
            ]
            [ if isOpen then
                AntIcons.folderOpenOutlined []

              else
                AntIcons.folderOutlined []
            ]
         , viewIf isOpen <| DocList.viewSmall msgs.noOp msgs.fileSearchChanged msgs.contextMenuOpened currentDocument fileFilter docList
         , div
            [ id "document-switcher-icon"
            , onClickStop msgs.clickedSwitcher
            , onMouseEnter <| msgs.tooltipRequested "document-switcher-icon" RightTooltip "Open quick switcher"
            , onMouseLeave msgs.tooltipClosed
            , class "sidebar-button"
            ]
            [ AntIcons.fileSearchOutlined [] ]
         , div
            [ id "help-icon"
            , class "sidebar-button"
            , classList [ ( "open", helpOpen ) ]
            , onClickStop msgs.clickedHelp
            , attributeIf (dropdownState /= Help) <| onMouseEnter <| msgs.tooltipRequested "help-icon" RightTooltip "Help"
            , onMouseLeave msgs.tooltipClosed
            ]
            [ AntIcons.questionCircleOutlined [] ]
         , div
            [ id "account-icon"
            , class "sidebar-button"
            , classList [ ( "open", accountOpen ) ]
            , onClickStop msgs.toggledAccount
            , onMouseEnter <| msgs.tooltipRequested "account-icon" RightTooltip "Account"
            , onMouseLeave msgs.tooltipClosed
            ]
            [ AntIcons.userOutlined [] ]
         ]
            ++ viewSidebarMenu lang
                { toggledShortcuts = msgs.toggledShortcuts
                , clickedEmailSupport = msgs.clickedEmailSupport
                , helpClosed = msgs.clickedHelp
                , logout = msgs.logout
                , accountClosed = msgs.toggledAccount
                , noOp = msgs.noOp
                }
                accountEmail
                dropdownState
        )


viewSidebarMenu :
    Language
    -> { toggledShortcuts : msg, clickedEmailSupport : msg, helpClosed : msg, logout : msg, accountClosed : msg, noOp : msg }
    -> String
    -> SidebarMenuState
    -> List (Html msg)
viewSidebarMenu lang msgs accountEmail dropdownState =
    case dropdownState of
        Help ->
            [ div [ id "help-menu", class "sidebar-menu" ]
                [ a [ href "https://docs.gingkowriter.com", target "_blank", onClickStop msgs.noOp ] [ text "FAQ" ]
                , div [ onClickStop msgs.toggledShortcuts ] [ text <| tr lang KeyboardHelp ]
                , div [ onClickStop msgs.clickedEmailSupport ] [ text <| tr lang EmailSupport ]
                ]
            , div [ id "help-menu-exit-top", onMouseEnter msgs.helpClosed ] []
            , div [ id "help-menu-exit-right", onMouseEnter msgs.helpClosed ] []
            ]

        Account ->
            [ div [ id "account-menu", class "sidebar-menu" ]
                [ div [ onClickStop msgs.noOp ] [ text accountEmail ]
                , div [ onClickStop msgs.logout ] [ text <| tr lang Logout ]
                ]
            , div [ id "help-menu-exit-top", onMouseEnter msgs.accountClosed ] []
            , div [ id "help-menu-exit-right", onMouseEnter msgs.accountClosed ] []
            ]

        NoSidebarMenu ->
            [ text "" ]


viewSidebarStatic : Bool -> List (Html msg)
viewSidebarStatic sidebarOpen =
    [ div [ id "sidebar", classList [ ( "open", sidebarOpen ) ] ]
        [ div [ classList [ ( "sidebar-button", True ) ] ] [ text " " ]
        ]
    , if sidebarOpen then
        div [ id "sidebar-menu" ]
            [ h3 [] [ text "File" ]
            , a [ href (Route.toString Route.DocNew), class "sidebar-item" ] [ text "New" ]
            , hr [ style "width" "80%" ] []
            ]

      else
        text ""
    ]


viewLoadingSpinner : msg -> Bool -> Html msg
viewLoadingSpinner toggleSidebarMsg sidebarOpen =
    div [ id "app-root", class "loading" ]
        ([ div [ id "document-header" ] []
         , div [ id "loading-overlay" ] []
         , div [ class "spinner" ] [ div [ class "bounce1" ] [], div [ class "bounce2" ] [], div [ class "bounce3" ] [] ]
         ]
            ++ viewSidebarStatic sidebarOpen
        )



-- MODALS


viewTemplateSelector :
    Language
    -> { modalClosed : msg, importBulkClicked : msg, importJSONRequested : msg }
    -> List (Html msg)
viewTemplateSelector language msgs =
    [ div [ id "templates-block" ]
        [ a [ id "template-new", class "template-item", href (Route.toString Route.DocNew) ]
            [ div [ classList [ ( "template-thumbnail", True ), ( "new", True ) ] ] []
            , div [ class "template-title" ] [ text <| tr language HomeBlank ]
            ]
        , div [ id "template-import-bulk", class "template-item", onClick msgs.importBulkClicked ]
            [ div [ classList [ ( "template-thumbnail", True ) ] ] [ Icon.fileZip (Icon.defaultOptions |> Icon.size 48) ]
            , div [ class "template-title" ] [ text <| tr language HomeImportLegacy ]
            , div [ class "template-description" ]
                [ text <| tr language HomeLegacyFrom ]
            ]
        , div [ id "template-import", class "template-item", onClick msgs.importJSONRequested ]
            [ div [ classList [ ( "template-thumbnail", True ) ] ] [ Icon.fileCode (Icon.defaultOptions |> Icon.size 48) ]
            , div [ class "template-title" ] [ text <| tr language HomeImportJSON ]
            , div [ class "template-description" ]
                [ text <| tr language HomeJSONFrom ]
            ]
        , a [ id "template-timeline", class "template-item", href <| Route.toString (Route.Import Timeline) ]
            [ div [ classList [ ( "template-thumbnail", True ) ] ] [ Icon.lightBulb (Icon.defaultOptions |> Icon.size 48) ]
            , div [ class "template-title" ] [ text "Timeline 2021" ]
            , div [ class "template-description" ]
                [ text "A tree-based calendar" ]
            ]
        , a [ id "template-academic", class "template-item", href <| Route.toString (Route.Import AcademicPaper) ]
            [ div [ classList [ ( "template-thumbnail", True ) ] ] [ Icon.lightBulb (Icon.defaultOptions |> Icon.size 48) ]
            , div [ class "template-title" ] [ text "Academic Paper" ]
            , div [ class "template-description" ]
                [ text "Starting point for journal paper" ]
            ]
        , a [ id "template-project", class "template-item", href <| Route.toString (Route.Import ProjectBrainstorming) ]
            [ div [ classList [ ( "template-thumbnail", True ) ] ] [ Icon.lightBulb (Icon.defaultOptions |> Icon.size 48) ]
            , div [ class "template-title" ] [ text "Project Brainstorming" ]
            , div [ class "template-description" ]
                [ text "Clarify project goals" ]
            ]
        , a [ id "template-heros-journey", class "template-item", href <| Route.toString (Route.Import HerosJourney) ]
            [ div [ classList [ ( "template-thumbnail", True ) ] ] [ Icon.lightBulb (Icon.defaultOptions |> Icon.size 48) ]
            , div [ class "template-title" ] [ text "Hero's Journey" ]
            , div [ class "template-description" ]
                [ text "A framework for fictional stories" ]
            ]
        ]
    ]
        |> modalWrapper msgs.modalClosed Nothing "New Document"


viewWordCount :
    { m
        | viewState : ViewState
        , workingTree : TreeStructure.Model
        , startingWordcount : Int
        , wordcountTrayOpen : Bool
        , session : Session
    }
    -> { modalClosed : msg }
    -> List (Html msg)
viewWordCount model msgs =
    let
        language =
            Session.language model.session

        stats =
            getStats model

        current =
            stats.documentWords

        session =
            current - model.startingWordcount
    in
    [ span [] [ text (tr language (WordCountSession session)) ]
    , span [] [ text (tr language (WordCountTotal current)) ]
    , span [] [ text (tr language (WordCountCard stats.cardWords)) ]
    , span [] [ text (tr language (WordCountSubtree stats.subtreeWords)) ]
    , span [] [ text (tr language (WordCountGroup stats.groupWords)) ]
    , span [] [ text (tr language (WordCountColumn stats.columnWords)) ]
    , hr [] []
    , span [] [ text ("Total Cards in Tree : " ++ String.fromInt stats.cards) ]
    ]
        |> modalWrapper msgs.modalClosed Nothing "Word Counts"



-- DOCUMENT


viewSearchField : (String -> msg) -> { m | viewState : ViewState, session : Session } -> Html msg
viewSearchField searchFieldMsg { viewState, session } =
    let
        language =
            Session.language session

        maybeSearchIcon =
            if viewState.searchField == Nothing then
                Icon.search (defaultOptions |> Icon.color "#445" |> Icon.size 12)

            else
                text ""
    in
    case viewState.viewMode of
        Normal ->
            div
                [ id "search-field" ]
                [ input
                    [ type_ "search"
                    , id "search-input"
                    , required True
                    , title (tr language PressToSearch)
                    , onInput searchFieldMsg
                    ]
                    []
                , maybeSearchIcon
                ]

        _ ->
            div
                [ id "search-field" ]
                []


viewMobileButtons :
    { edit : msg
    , save : msg
    , cancel : msg
    , plusRight : msg
    , plusDown : msg
    , plusUp : msg
    , navLeft : msg
    , navUp : msg
    , navDown : msg
    , navRight : msg
    }
    -> Bool
    -> Html msg
viewMobileButtons msgs isEditing =
    if isEditing then
        div [ id "mobile-buttons", class "footer" ]
            [ span [ id "mbtn-cancel", class "mobile-button", onClick msgs.cancel ] [ AntIcons.stopOutlined [ width 18 ] ]
            , span [ id "mbtn-save", class "mobile-button", onClick msgs.save ] [ AntIcons.checkOutlined [ width 18 ] ]
            ]

    else
        div [ id "mobile-buttons", class "footer" ]
            [ span [ id "mbtn-edit", class "mobile-button", onClick msgs.edit ] [ AntIcons.editTwoTone [ width 18 ] ]
            , span [ id "mbtn-add-right", class "mobile-button", onClick msgs.plusRight ] [ AntIcons.plusSquareTwoTone [ width 18 ], AntIcons.rightOutlined [ width 14 ] ]
            , span [ id "mbtn-add-down", class "mobile-button", onClick msgs.plusDown ] [ AntIcons.plusSquareTwoTone [ width 18 ], AntIcons.downOutlined [ width 14 ] ]
            , span [ id "mbtn-add-up", class "mobile-button", onClick msgs.plusUp ] [ AntIcons.plusSquareTwoTone [ width 18 ], AntIcons.upOutlined [ width 14 ] ]
            , span [ id "mbtn-nav-left", class "mobile-button", onClick msgs.navLeft ] [ AntIcons.caretLeftOutlined [ width 18 ] ]
            , span [ id "mbtn-nav-up", class "mobile-button", onClick msgs.navUp ] [ AntIcons.caretUpOutlined [ width 18 ] ]
            , span [ id "mbtn-nav-down", class "mobile-button", onClick msgs.navDown ] [ AntIcons.caretDownOutlined [ width 18 ] ]
            , span [ id "mbtn-nav-right", class "mobile-button", onClick msgs.navRight ] [ AntIcons.caretRightOutlined [ width 18 ] ]
            ]


viewHistory : msg -> (String -> msg) -> msg -> msg -> Translation.Language -> String -> Data.Model -> Html msg
viewHistory noopMsg checkoutMsg restoreMsg cancelMsg lang currHead dataModel =
    let
        master =
            Data.head "heads/master" dataModel

        historyList =
            Data.historyList currHead dataModel

        maxIdx =
            historyList
                |> List.length
                |> (\x -> x - 1)
                |> String.fromInt

        currIdx =
            historyList
                |> ListExtra.elemIndex currHead
                |> Maybe.map String.fromInt
                |> Maybe.withDefault maxIdx

        checkoutCommit idxStr =
            case String.toInt idxStr of
                Just idx ->
                    case getAt idx historyList of
                        Just commit ->
                            checkoutMsg commit

                        Nothing ->
                            noopMsg

                Nothing ->
                    noopMsg
    in
    div [ id "history" ]
        [ input [ type_ "range", A.min "0", A.max maxIdx, step "1", onInput checkoutCommit ] []
        , button [ id "history-restore", onClick restoreMsg ] [ text <| tr lang RestoreThisVersion ]
        , button [ onClick cancelMsg ] [ text <| tr lang Cancel ]
        ]


viewVideo : (Bool -> msg) -> { m | videoModalOpen : Bool } -> Html msg
viewVideo modalMsg { videoModalOpen } =
    if videoModalOpen then
        div [ class "modal-container" ]
            [ div [ class "modal" ]
                [ div [ class "modal-header" ]
                    [ h1 [] [ text "Learning Videos" ]
                    , a [ onClick (modalMsg False) ] [ text "×" ]
                    ]
                , iframe
                    [ width 650
                    , height 366
                    , src "https://www.youtube.com/embed/ZOGgwKAU3vg?rel=0&amp;showinfo=0"
                    , attribute "frameborder" "0"
                    , attribute "allowfullscreen" ""
                    ]
                    []
                ]
            ]

    else
        div [] []


viewShortcuts : msg -> Language -> Bool -> Bool -> Children -> TextCursorInfo -> ViewState -> List (Html msg)
viewShortcuts trayToggleMsg lang isOpen isMac children textCursorInfo vs =
    let
        isTextSelected =
            textCursorInfo.selected

        isOnly =
            case children of
                Children [ singleRoot ] ->
                    if singleRoot.children == Children [] then
                        True

                    else
                        False

                _ ->
                    False

        viewIfNotOnly content =
            if not isOnly then
                content

            else
                text ""

        addInsteadOfSplit =
            textCursorInfo.position == End || textCursorInfo.position == Empty

        spanSplit key descAdd descSplit =
            if addInsteadOfSplit then
                shortcutSpan [ ctrlOrCmd, key ] descAdd

            else
                shortcutSpan [ ctrlOrCmd, key ] descSplit

        splitChild =
            spanSplit "L" (tr lang AddChildAction) (tr lang SplitChildAction)

        splitBelow =
            spanSplit "J" (tr lang AddBelowAction) (tr lang SplitBelowAction)

        splitAbove =
            spanSplit "K" (tr lang AddAboveAction) (tr lang SplitUpwardAction)

        shortcutSpanEnabled enabled keys desc =
            let
                keySpans =
                    keys
                        |> List.map (\k -> span [ class "shortcut-key" ] [ text k ])
            in
            span
                [ classList [ ( "disabled", not enabled ) ] ]
                (keySpans
                    ++ [ text (" " ++ desc) ]
                )

        shortcutSpan =
            shortcutSpanEnabled True

        formattingSpan markup =
            span [] [ pre [ class "formatting-text" ] [ text markup ] ]

        ctrlOrCmd =
            if isMac then
                "⌘"

            else
                "Ctrl"

        tourTooltip str =
            div [ id "welcome-step-5", class "tour-step" ]
                [ text "Shortcuts List"
                , div [ class "arrow" ] [ text "▶" ]
                , div [ id "progress-step-5", class "tour-step-progress" ]
                    [ div [ class "bg-line", class "on" ] []
                    , div [ class "bg-line", class "off" ] []
                    , div [ class "on" ] []
                    , div [ class "on" ] []
                    , div [ class "on" ] []
                    , div [ class "on" ] []
                    , div [ class "on" ] []
                    , div [] []
                    , div [] []
                    ]
                ]
    in
    if isOpen then
        let
            iconColor =
                Icon.color "#445"
        in
        case vs.viewMode of
            Normal ->
                [ div
                    [ id "shortcuts-tray", classList [ ( "open", isOpen ) ], onClick trayToggleMsg ]
                    [ div [ id "shortcuts" ]
                        [ h3 [] [ text "Keyboard Shortcuts", tourTooltip "Shortcuts List" ]
                        , h5 [] [ text "Edit Cards" ]
                        , shortcutSpan [ tr lang EnterKey ] (tr lang EnterAction)
                        , shortcutSpan [ "Shift", tr lang EnterKey ] (tr lang EditFullscreenAction)
                        , viewIfNotOnly <| h5 [] [ text "Navigate" ]
                        , viewIfNotOnly <| shortcutSpan [ "↑", "↓", "←", "→" ] (tr lang ArrowsAction)
                        , h5 [] [ text "Add New Cards" ]
                        , shortcutSpan [ ctrlOrCmd, "→" ] (tr lang AddChildAction)
                        , shortcutSpan [ ctrlOrCmd, "↓" ] (tr lang AddBelowAction)
                        , shortcutSpan [ ctrlOrCmd, "↑" ] (tr lang AddAboveAction)
                        , viewIfNotOnly <| h5 [] [ text "Move Cards" ]
                        , viewIfNotOnly <| shortcutSpan [ "Alt", tr lang ArrowKeys ] (tr lang MoveAction)
                        , viewIfNotOnly <| shortcutSpan [ ctrlOrCmd, tr lang Backspace ] (tr lang DeleteAction)
                        , viewIfNotOnly <| h5 [] [ text "Merge Cards" ]
                        , viewIfNotOnly <| shortcutSpan [ ctrlOrCmd, "Shift", "↓" ] (tr lang MergeDownAction)
                        , viewIfNotOnly <| shortcutSpan [ ctrlOrCmd, "Shift", "↑" ] (tr lang MergeUpAction)
                        , hr [] []
                        , h5 [] [ text "Other Shortcuts" ]
                        , shortcutSpan [ "w" ] "Display word counts"
                        , shortcutSpan [ ctrlOrCmd, "O" ] (tr lang QuickDocumentSwitcher)
                        ]
                    ]
                ]

            _ ->
                [ div
                    [ id "shortcuts-tray", classList [ ( "open", isOpen ) ], onClick trayToggleMsg ]
                    [ div [ id "shortcuts" ]
                        [ h3 [] [ text "Keyboard Shortcuts" ]
                        , h3 [] [ text "(Edit Mode)" ]
                        , h5 [] [ text "Save/Cancel Changes" ]
                        , shortcutSpan [ ctrlOrCmd, tr lang EnterKey ] (tr lang ToSaveChanges)
                        , shortcutSpan [ tr lang EscKey ] (tr lang ToCancelChanges)
                        , if addInsteadOfSplit then
                            h5 [] [ text "Add New Cards" ]

                          else
                            h5 [] [ text "Split At Cursor" ]
                        , splitChild
                        , splitBelow
                        , splitAbove
                        , h5 [] [ text "Formatting" ]
                        , shortcutSpanEnabled isTextSelected [ ctrlOrCmd, "B" ] (tr lang ForBold)
                        , shortcutSpanEnabled isTextSelected [ ctrlOrCmd, "I" ] (tr lang ForItalic)
                        , shortcutSpan [ "Alt", "(number)" ] "Set heading level (0-6)"
                        , formattingSpan "# Title\n## Subtitle"
                        , formattingSpan "- List item\n  - Subitem"
                        , formattingSpan "[link](http://t.co)"
                        , span [ class "markdown-guide" ]
                            [ a [ href "http://commonmark.org/help", target "_blank" ]
                                [ text <| tr lang FormattingGuide
                                , span [ class "icon-container" ] [ Icon.linkExternal (defaultOptions |> iconColor |> Icon.size 14) ]
                                ]
                            ]
                        ]
                    ]
                ]

    else
        let
            iconColor =
                Icon.color "#6c7c84"
        in
        [ div
            [ id "shortcuts-tray", onClick trayToggleMsg, title <| tr lang KeyboardHelp ]
            [ div [ classList [ ( "icon-stack", True ), ( "open", isOpen ) ] ]
                [ Icon.keyboard (defaultOptions |> iconColor) ]
            ]
        ]



-- Word count


type alias Stats =
    { cardWords : Int
    , subtreeWords : Int
    , groupWords : Int
    , columnWords : Int
    , documentWords : Int
    , cards : Int
    }


viewWordcountProgress : Int -> Int -> Html msg
viewWordcountProgress current session =
    let
        currW =
            1 / (1 + toFloat session / toFloat current)

        sessW =
            1 - currW
    in
    div [ id "wc-progress" ]
        [ div [ id "wc-progress-wrap" ]
            [ span [ style "flex" (String.fromFloat currW), id "wc-progress-bar" ] []
            , span [ style "flex" (String.fromFloat sessW), id "wc-progress-bar-session" ] []
            ]
        ]


viewTooltip : ( Element, TooltipPosition, String ) -> Html msg
viewTooltip ( el, tipPos, content ) =
    let
        posAttributes =
            case tipPos of
                RightTooltip ->
                    [ style "left" <| ((el.element.x + el.element.width + 5) |> String.fromFloat) ++ "px"
                    , style "top" <| ((el.element.y + el.element.height * 0.5) |> String.fromFloat) ++ "px"
                    , style "transform" "translateY(-50%)"
                    , class "tip-right"
                    ]

                LeftTooltip ->
                    [ style "left" <| ((el.element.x - 5) |> String.fromFloat) ++ "px"
                    , style "top" <| ((el.element.y + el.element.height * 0.5) |> String.fromFloat) ++ "px"
                    , style "transform" "translate(-100%, -50%)"
                    , class "tip-left"
                    ]

                BelowTooltip ->
                    [ style "left" <| ((el.element.x + el.element.width * 0.5) |> String.fromFloat) ++ "px"
                    , style "top" <| ((el.element.y + el.element.height + 5) |> String.fromFloat) ++ "px"
                    , style "transform" "translateX(-50%)"
                    , class "tip-below"
                    ]

                BelowLeftTooltip ->
                    [ style "left" <| ((el.element.x + el.element.width * 0.5) |> String.fromFloat) ++ "px"
                    , style "top" <| ((el.element.y + el.element.height + 5) |> String.fromFloat) ++ "px"
                    , style "transform" "translateX(calc(-100% + 5px))"
                    , class "tip-below-left"
                    ]
    in
    div ([ class "tooltip" ] ++ posAttributes)
        [ text content, div [ class "tooltip-arrow" ] [] ]


getStats : { m | viewState : ViewState, workingTree : TreeStructure.Model } -> Stats
getStats model =
    let
        activeCardId =
            model.viewState.active

        tree =
            model.workingTree.tree

        cardsTotal =
            (model.workingTree.tree
                |> TreeUtils.preorderTraversal
                |> List.length
            )
                -- Don't count hidden root
                - 1

        currentTree =
            getTree activeCardId tree
                |> Maybe.withDefault defaultTree

        currentGroup =
            getSiblings activeCardId tree

        cardCount =
            countWords currentTree.content

        subtreeCount =
            cardCount + countWords (treeToMarkdownString False currentTree)

        groupCount =
            currentGroup
                |> List.map .content
                |> String.join "\n\n"
                |> countWords

        columnCount =
            getColumn (getDepth 0 tree activeCardId) tree
                -- Maybe (List (List Tree))
                |> Maybe.withDefault [ [] ]
                |> List.concat
                |> List.map .content
                |> String.join "\n\n"
                |> countWords

        treeCount =
            countWords (treeToMarkdownString False tree)
    in
    Stats
        cardCount
        subtreeCount
        groupCount
        columnCount
        treeCount
        cardsTotal


countWords : String -> Int
countWords str =
    let
        punctuation =
            Regex.fromString "[!@#$%^&*():;\"',.]+"
                |> Maybe.withDefault Regex.never
    in
    str
        |> String.toLower
        |> replace punctuation (\_ -> "")
        |> String.words
        |> List.filter ((/=) "")
        |> List.length


viewConflict : (String -> Selection -> String -> msg) -> (String -> msg) -> Conflict -> Html msg
viewConflict setSelectionMsg resolveMsg { id, opA, opB, selection, resolved } =
    let
        withManual cardId oursElement theirsElement =
            li
                []
                [ fieldset []
                    [ radio (setSelectionMsg id Original cardId) (selection == Original) (text "Original")
                    , radio (setSelectionMsg id Ours cardId) (selection == Ours) oursElement
                    , radio (setSelectionMsg id Theirs cardId) (selection == Theirs) theirsElement
                    , radio (setSelectionMsg id Manual cardId) (selection == Manual) (text "Merged")
                    , label []
                        [ input [ checked resolved, type_ "checkbox", onClick (resolveMsg id) ] []
                        , text "Resolved"
                        ]
                    ]
                ]

        withoutManual cardIdA cardIdB =
            li
                []
                [ fieldset []
                    [ radio (setSelectionMsg id Original "") (selection == Original) (text "Original")
                    , radio (setSelectionMsg id Ours cardIdA) (selection == Ours) (text ("Ours:" ++ (opString opA |> String.left 3)))
                    , radio (setSelectionMsg id Theirs cardIdB) (selection == Theirs) (text ("Theirs:" ++ (opString opB |> String.left 3)))
                    , label []
                        [ input [ checked resolved, type_ "checkbox", onClick (resolveMsg id) ] []
                        , text "Resolved"
                        ]
                    ]
                ]

        newConflictView cardId ourChanges theirChanges =
            div [ class "flex-row" ]
                [ div [ class "conflict-container flex-column" ]
                    [ div
                        [ classList [ ( "row option", True ), ( "selected", selection == Original ) ]
                        , onClick (setSelectionMsg id Original cardId)
                        ]
                        [ text "Original" ]
                    , div [ class "row flex-row" ]
                        [ div
                            [ classList [ ( "option", True ), ( "selected", selection == Ours ) ]
                            , onClick (setSelectionMsg id Ours cardId)
                            ]
                            [ text "Ours"
                            , ul [ class "changelist" ] ourChanges
                            ]
                        , div
                            [ classList [ ( "option", True ), ( "selected", selection == Theirs ) ]
                            , onClick (setSelectionMsg id Theirs cardId)
                            ]
                            [ text "Theirs"
                            , ul [ class "changelist" ] theirChanges
                            ]
                        ]
                    , div
                        [ classList [ ( "row option", True ), ( "selected", selection == Manual ) ]
                        , onClick (setSelectionMsg id Manual cardId)
                        ]
                        [ text "Merged" ]
                    ]
                , button [ onClick (resolveMsg id) ] [ text "Resolved" ]
                ]
    in
    case ( opA, opB ) of
        ( Mod idA _ _ _, Mod _ _ _ _ ) ->
            let
                diffLinesString l r =
                    diffLines l r
                        |> List.filterMap
                            (\c ->
                                case c of
                                    NoChange s ->
                                        Nothing

                                    Added s ->
                                        Just (li [] [ ins [ class "diff" ] [ text s ] ])

                                    Removed s ->
                                        Just (li [] [ del [ class "diff" ] [ text s ] ])
                            )
            in
            newConflictView idA [] []

        ( Conflict.Ins idA _ _ _, Del idB _ ) ->
            withoutManual idA idB

        ( Del idA _, Conflict.Ins idB _ _ _ ) ->
            withoutManual idA idB

        _ ->
            withoutManual "" ""


radio : msg -> Bool -> Html msg -> Html msg
radio msg bool labelElement =
    label []
        [ input [ type_ "radio", checked bool, onClick msg ] []
        , labelElement
        ]


onClickStop : msg -> Html.Attribute msg
onClickStop msg =
    stopPropagationOn "click" (Dec.succeed ( msg, True ))
