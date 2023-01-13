module Doc.UI exposing (countWords, fillet, viewAppLoadingSpinner, viewBreadcrumbs, viewConflict, viewDocumentLoadingSpinner, viewExportMenu, viewHeader, viewMobileButtons, viewSaveIndicator, viewSearchField, viewShortcuts, viewTemplateSelector, viewTooltip, viewWordCount)

import Ant.Icons.Svg as AntIcons
import Browser.Dom exposing (Element)
import Coders exposing (treeToMarkdownString)
import Diff exposing (..)
import Doc.Data as Data exposing (CommitObject)
import Doc.Data.Conflict as Conflict exposing (Conflict, Op(..), Selection(..), opString)
import Doc.History as History
import Doc.TreeStructure as TreeStructure exposing (defaultTree)
import Doc.TreeUtils as TreeUtils exposing (..)
import GlobalData exposing (GlobalData)
import Html exposing (Html, a, br, button, del, div, fieldset, h2, h3, h4, h5, hr, img, input, ins, label, li, pre, span, ul)
import Html.Attributes exposing (..)
import Html.Attributes.Extra exposing (attributeIf)
import Html.Events exposing (keyCode, on, onBlur, onClick, onFocus, onInput, onMouseEnter, onMouseLeave)
import Html.Extra exposing (viewIf)
import Import.Template exposing (Template(..))
import Json.Decode as Dec
import Markdown.Block
import Markdown.Html
import Markdown.Parser
import Markdown.Renderer exposing (Renderer)
import Octicons as Icon exposing (defaultOptions)
import Page.Doc.Export exposing (ExportFormat(..), ExportSelection(..))
import Page.Doc.Theme exposing (Theme(..))
import Regex exposing (Regex, replace)
import Route
import Session exposing (PaymentStatus(..), Session)
import SharedUI exposing (ctrlOrCmdText, modalWrapper)
import Svg exposing (g, svg)
import Svg.Attributes exposing (d, fill, fontFamily, fontSize, fontWeight, preserveAspectRatio, stroke, strokeDasharray, strokeDashoffset, strokeLinecap, strokeLinejoin, strokeMiterlimit, strokeWidth, textAnchor, version, viewBox)
import Time exposing (posixToMillis)
import Translation exposing (Language(..), TranslationId(..), timeDistInWords, tr)
import Types exposing (Children(..), CursorPosition(..), HeaderMenuState(..), SortBy(..), TextCursorInfo, TooltipPosition(..), ViewMode(..), ViewState)
import UI.Sidebar exposing (viewSidebarStatic)
import Utils exposing (emptyText, text, textNoTr)



-- HEADER


viewHeader :
    { noOp : msg
    , titleFocused : msg
    , titleFieldChanged : String -> msg
    , titleEdited : msg
    , titleEditCanceled : msg
    , tooltipRequested : String -> TooltipPosition -> TranslationId -> msg
    , tooltipClosed : msg
    , toggledHistory : Bool -> msg
    , checkoutCommit : String -> msg
    , restore : msg
    , cancelHistory : msg
    , toggledDocSettings : msg
    , wordCountClicked : msg
    , themeChanged : Theme -> msg
    , toggledExport : msg
    , exportSelectionChanged : ExportSelection -> msg
    , exportFormatChanged : ExportFormat -> msg
    , export : msg
    , printRequested : msg
    , toggledUpgradeModal : Bool -> msg
    }
    ->
        { session : Session
        , title_ : Maybe String
        , titleField_ : Maybe String
        , headerMenu : HeaderMenuState
        , exportSettings : ( ExportSelection, ExportFormat )
        , data : Data.Model
        , dirty : Bool
        , lastLocalSave : Maybe Time.Posix
        , lastRemoteSave : Maybe Time.Posix
        , globalData : GlobalData
        }
    -> Html msg
viewHeader msgs { session, title_, titleField_, headerMenu, exportSettings, data, dirty, lastLocalSave, lastRemoteSave, globalData } =
    let
        language =
            GlobalData.language globalData

        currentTime =
            GlobalData.currentTime globalData

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
                    titleField_ |> Maybe.withDefault "Untitled"
            in
            span [ id "title" ]
                [ div [ class "title-grow-wrap" ]
                    [ div [ class "shadow" ]
                        [ Html.text <|
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
                , viewSaveIndicator language
                    { dirty = dirty, lastLocalSave = lastLocalSave, lastRemoteSave = lastRemoteSave }
                    (GlobalData.currentTime globalData)
                ]

        isHistoryView =
            case headerMenu of
                HistoryView _ ->
                    True

                _ ->
                    False
    in
    div [ id "document-header" ]
        [ titleArea
        , div
            [ id "history-icon"
            , class "header-button"
            , classList [ ( "open", isHistoryView ) ]
            , onClick <| msgs.toggledHistory (not isHistoryView)
            , attributeIf (not isHistoryView) <| onMouseEnter <| msgs.tooltipRequested "history-icon" BelowTooltip VersionHistory
            , onMouseLeave msgs.tooltipClosed
            ]
            [ AntIcons.historyOutlined [] ]
        , case headerMenu of
            HistoryView historyState ->
                History.view
                    { lang = language
                    , toSelf = always msgs.noOp
                    , restore = msgs.restore
                    , cancel = msgs.cancelHistory
                    , tooltipRequested = msgs.tooltipRequested
                    , tooltipClosed = msgs.tooltipClosed
                    }
                    (Data.history historyState.currentView data)

            _ ->
                emptyText
        , div
            [ id "doc-settings-icon"
            , class "header-button"
            , classList [ ( "open", headerMenu == Settings ) ]
            , onClick msgs.toggledDocSettings
            , attributeIf (headerMenu /= Settings) <| onMouseEnter <| msgs.tooltipRequested "doc-settings-icon" BelowLeftTooltip DocumentSettings
            , onMouseLeave msgs.tooltipClosed
            ]
            [ AntIcons.controlOutlined [] ]
        , viewIf (headerMenu == Settings) <|
            div [ id "doc-settings-menu", class "header-menu" ]
                [ div [ id "wordcount-menu-item", onClick msgs.wordCountClicked ] [ text language WordCount ]
                , h4 [] [ text language DocumentTheme ]
                , div [ onClick <| msgs.themeChanged Default ] [ text language ThemeDefault ]
                , div [ onClick <| msgs.themeChanged Dark ] [ text language ThemeDarkMode ]
                , div [ onClick <| msgs.themeChanged Classic ] [ text language ThemeClassic ]
                , div [ onClick <| msgs.themeChanged Gray ] [ text language ThemeGray ]
                , div [ onClick <| msgs.themeChanged Green ] [ text language ThemeGreen ]
                , div [ onClick <| msgs.themeChanged Turquoise ] [ text language ThemeTurquoise ]
                ]
        , viewIf (headerMenu == Settings) <| div [ id "doc-settings-menu-exit-left", onMouseEnter msgs.toggledDocSettings ] []
        , viewIf (headerMenu == Settings) <| div [ id "doc-settings-menu-exit-bottom", onMouseEnter msgs.toggledDocSettings ] []
        , div
            [ id "export-icon"
            , class "header-button"
            , classList [ ( "open", headerMenu == ExportPreview ) ]
            , onClick msgs.toggledExport
            , attributeIf (headerMenu /= ExportPreview) <| onMouseEnter <| msgs.tooltipRequested "export-icon" BelowLeftTooltip ExportOrPrint
            , onMouseLeave msgs.tooltipClosed
            ]
            [ AntIcons.fileDoneOutlined [] ]
        , viewUpgradeButton
            msgs.toggledUpgradeModal
            globalData
            session
        , viewIf (headerMenu == ExportPreview) <| viewExportMenu language msgs False exportSettings
        ]


viewExportMenu :
    Language
    ->
        { m
            | exportSelectionChanged : ExportSelection -> msg
            , exportFormatChanged : ExportFormat -> msg
            , toggledExport : msg
            , tooltipRequested : String -> TooltipPosition -> TranslationId -> msg
            , tooltipClosed : msg
        }
    -> Bool
    -> ( ExportSelection, ExportFormat )
    -> Html msg
viewExportMenu language msgs showCloseButton ( exportSelection, exportFormat ) =
    let
        exportSelectionBtnAttributes expSel expSelString tooltipText =
            [ id <| "export-select-" ++ expSelString
            , onClick <| msgs.exportSelectionChanged expSel
            , classList [ ( "selected", expSel == exportSelection ) ]
            , onMouseEnter <| msgs.tooltipRequested ("export-select-" ++ expSelString) BelowTooltip tooltipText
            , onMouseLeave msgs.tooltipClosed
            ]

        exportFormatBtnAttributes expFormat expFormatString =
            [ id <| "export-format-" ++ expFormatString
            , onClick <| msgs.exportFormatChanged expFormat
            , classList [ ( "selected", expFormat == exportFormat ) ]
            ]
    in
    div [ id "export-menu" ]
        ([ div [ id "export-selection", class "toggle-button" ]
            [ div (exportSelectionBtnAttributes ExportEverything "all" ExportSettingEverythingDesc) [ text language ExportSettingEverything ]
            , div (exportSelectionBtnAttributes ExportSubtree "subtree" ExportSettingCurrentSubtreeDesc) [ text language ExportSettingCurrentSubtree ]
            , div (exportSelectionBtnAttributes ExportLeaves "leaves" ExportSettingLeavesOnlyDesc) [ text language ExportSettingLeavesOnly ]
            , div (exportSelectionBtnAttributes ExportCurrentColumn "column" ExportSettingCurrentColumnDesc) [ text language ExportSettingCurrentColumn ]
            ]
         , div [ id "export-format", class "toggle-button" ]
            [ div (exportFormatBtnAttributes DOCX "word") [ text language ExportSettingWord ]
            , div (exportFormatBtnAttributes PlainText "text") [ text language ExportSettingPlainText ]
            , div (exportFormatBtnAttributes OPML "opml") [ text language ExportSettingOPML ]
            , div (exportFormatBtnAttributes JSON "json") [ text language ExportSettingJSON ]
            ]
         ]
            ++ (if showCloseButton then
                    [ span
                        [ id "export-button-close"
                        , onClick msgs.toggledExport
                        , onMouseEnter <| msgs.tooltipRequested "export-button-close" BelowLeftTooltip CloseExportView
                        , onMouseLeave msgs.tooltipClosed
                        ]
                        [ AntIcons.closeCircleOutlined [ width 16 ] ]
                    ]

                else
                    []
               )
        )


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
                span [ title (tr language LastSaved ++ " " ++ lastChangeString) ] [ text language UnsavedChanges ]

            else
                case ( lastLocalSave, lastRemoteSave ) of
                    ( Nothing, Nothing ) ->
                        span [] [ text language NeverSaved ]

                    ( Just time, Nothing ) ->
                        if Time.posixToMillis time == 0 then
                            span [] [ text language NeverSaved ]

                        else
                            span [ title (tr language LastEdit ++ " " ++ lastChangeString) ] [ text language SavedInternally ]

                    ( Just commitTime, Just fileTime ) ->
                        if posixToMillis commitTime <= posixToMillis fileTime then
                            span [ title (tr language LastEdit ++ " " ++ lastChangeString) ]
                                [ text language ChangesSynced ]

                        else
                            span [ title (tr language LastEdit ++ " " ++ lastChangeString) ] [ text language SavedInternally ]

                    ( Nothing, Just _ ) ->
                        span [ title (tr language LastEdit ++ " " ++ lastChangeString) ] [ text language DatabaseError ]
    in
    div
        [ id "save-indicator", classList [ ( "inset", True ), ( "saving", dirty ) ] ]
        [ saveStateSpan
        ]


viewUpgradeButton :
    (Bool -> msg)
    -> GlobalData
    -> Session
    -> Html msg
viewUpgradeButton toggledUpgradeModal globalData session =
    let
        lang =
            GlobalData.language globalData

        upgradeCTA isExpired prepends =
            div
                [ id "upgrade-cta"
                , onClick <| toggledUpgradeModal True
                , classList [ ( "trial-expired", isExpired ) ]
                ]
                (prepends ++ [ div [ id "upgrade-button" ] [ text lang Upgrade ] ])

        maybeUpgrade =
            case Session.daysLeft (GlobalData.currentTime globalData) session of
                Just daysLeft ->
                    let
                        trialClass =
                            if daysLeft <= 7 && daysLeft > 5 then
                                "trial-light"

                            else if daysLeft <= 5 && daysLeft > 3 then
                                "trial-medium"

                            else
                                "trial-dark"
                    in
                    if daysLeft <= 0 then
                        upgradeCTA True
                            [ span []
                                [ AntIcons.exclamationCircleOutlined [ width 16, style "margin-bottom" "-3px", style "margin-right" "6px" ]
                                , text lang TrialExpired
                                ]
                            ]

                    else if daysLeft <= 7 then
                        upgradeCTA False [ span [ class trialClass ] [ text lang (DaysLeft daysLeft) ] ]

                    else
                        upgradeCTA False []

                Nothing ->
                    emptyText
    in
    maybeUpgrade


viewBreadcrumbs : (String -> msg) -> List ( String, String ) -> Html msg
viewBreadcrumbs clickedCrumbMsg cardIdsAndTitles =
    let
        defaultMarkdown =
            Markdown.Renderer.defaultHtmlRenderer

        firstElementOnly : a -> List a -> a
        firstElementOnly d l =
            List.head l |> Maybe.withDefault d

        markdownParser tag =
            Markdown.Html.tag tag (\rc -> List.head rc |> Maybe.withDefault emptyText)

        textRenderer : Renderer (Html msg)
        textRenderer =
            { defaultMarkdown
                | text = Html.text
                , codeSpan = Html.text
                , image = always emptyText
                , heading = \{ rawText } -> Html.text (String.trim rawText)
                , paragraph = firstElementOnly emptyText
                , blockQuote = firstElementOnly emptyText
                , orderedList = \i l -> List.map (firstElementOnly emptyText) l |> firstElementOnly emptyText
                , unorderedList =
                    \l ->
                        List.map
                            (\li ->
                                case li of
                                    Markdown.Block.ListItem _ children ->
                                        children |> firstElementOnly emptyText
                            )
                            l
                            |> firstElementOnly emptyText
                , html = Markdown.Html.oneOf ([ "p", "h1", "h2", "h3", "h4", "h5", "h6", "style", "code", "span", "pre" ] |> List.map markdownParser)
            }

        renderedContent : String -> List (Html msg)
        renderedContent content =
            content
                |> Markdown.Parser.parse
                |> Result.mapError deadEndsToString
                |> Result.andThen (\ast -> Markdown.Renderer.render textRenderer ast)
                |> Result.withDefault [ Html.text "<parse error>" ]

        deadEndsToString deadEnds =
            deadEnds
                |> List.map Markdown.Parser.deadEndToString
                |> String.join "\n"

        viewCrumb ( id, content ) =
            div [ onClick <| clickedCrumbMsg id ] [ span [] (renderedContent content) ]
    in
    div [ id "breadcrumbs", attribute "data-private" "lipsum" ] (List.map viewCrumb cardIdsAndTitles)



-- SIDEBAR


viewAppLoadingSpinner : Bool -> Html msg
viewAppLoadingSpinner sidebarOpen =
    div [ id "app-root", class "loading" ]
        ([ div [ id "document-header" ] []
         , div [ id "loading-overlay" ] []
         , div [ class "spinner" ] [ div [ class "bounce1" ] [], div [ class "bounce2" ] [], div [ class "bounce3" ] [] ]
         ]
            ++ viewSidebarStatic sidebarOpen
        )


viewDocumentLoadingSpinner : List (Html msg)
viewDocumentLoadingSpinner =
    [ div [ id "document-header" ] []
    , div [ id "loading-overlay" ] []
    , div [ class "spinner" ] [ div [ class "bounce1" ] [], div [ class "bounce2" ] [], div [ class "bounce3" ] [] ]
    ]



-- MODALS


viewTemplateSelector :
    Language
    ->
        { modalClosed : msg
        , importBulkClicked : msg
        , importTextClicked : msg
        , importOpmlRequested : msg
        , importJSONRequested : msg
        }
    -> List (Html msg)
viewTemplateSelector language msgs =
    [ div [ id "templates-block" ]
        [ h2 [] [ text language New ]
        , div [ class "template-row" ]
            [ a [ id "template-new", class "template-item", href (Route.toString Route.DocNew) ]
                [ div [ classList [ ( "template-thumbnail", True ), ( "new", True ) ] ] []
                , div [ class "template-title" ] [ text language HomeBlank ]
                ]
            ]
        , h2 [] [ text language ImportSectionTitle ]
        , div [ class "template-row" ]
            [ div [ id "template-import-bulk", class "template-item", onClick msgs.importBulkClicked ]
                [ div [ classList [ ( "template-thumbnail", True ) ] ] [ Icon.fileZip (Icon.defaultOptions |> Icon.size 48) ]
                , div [ class "template-title" ] [ text language HomeImportLegacy ]
                , div [ class "template-description" ]
                    [ text language HomeLegacyFrom ]
                ]
            , div [ id "template-import-text", class "template-item", onClick msgs.importTextClicked ]
                [ div [ classList [ ( "template-thumbnail", True ) ] ] [ Icon.file (Icon.defaultOptions |> Icon.size 48) ]
                , div [ class "template-title" ] [ text language ImportTextFiles ]
                , div [ class "template-description" ]
                    [ text language ImportTextFilesDesc ]
                ]
            , div [ id "template-import", class "template-item", onClick msgs.importJSONRequested ]
                [ div [ classList [ ( "template-thumbnail", True ) ] ] [ Icon.fileCode (Icon.defaultOptions |> Icon.size 48) ]
                , div [ class "template-title" ] [ text language HomeImportJSON ]
                , div [ class "template-description" ]
                    [ text language HomeJSONFrom ]
                ]
            , div [ id "template-import-opml", class "template-item", onClick msgs.importOpmlRequested ]
                [ div [ classList [ ( "template-thumbnail", True ) ] ] [ Icon.fileCode (Icon.defaultOptions |> Icon.size 48) ]
                , div [ class "template-title" ] [ text language ImportOpmlFiles ]
                , div [ class "template-description" ]
                    [ text language ImportOpmlFilesDesc ]
                ]
            ]
        , h2 [] [ text language TemplatesAndExamples ]
        , div [ class "template-row" ]
            [ a [ id "template-timeline", class "template-item", href <| Route.toString (Route.Import Timeline) ]
                [ div [ classList [ ( "template-thumbnail", True ) ] ] [ AntIcons.calendarOutlined [ width 48, height 48 ] ]
                , div [ class "template-title" ] [ text language TimelineTemplate ]
                , div [ class "template-description" ]
                    [ text language TimelineTemplateDesc ]
                ]
            , a [ id "template-academic", class "template-item", href <| Route.toString (Route.Import AcademicPaper) ]
                [ div [ classList [ ( "template-thumbnail", True ) ] ] [ AntIcons.experimentOutlined [ width 48, height 48 ] ]
                , div [ class "template-title" ] [ text language AcademicPaperTemplate ]
                , div [ class "template-description" ]
                    [ text language AcademicPaperTemplateDesc ]
                ]
            , a [ id "template-project", class "template-item", href <| Route.toString (Route.Import ProjectBrainstorming) ]
                [ div [ classList [ ( "template-thumbnail", True ) ] ] [ AntIcons.bulbOutlined [ width 48, height 48 ] ]
                , div [ class "template-title" ] [ text language ProjectBrainstormingTemplate ]
                , div [ class "template-description" ]
                    [ text language ProjectBrainstormingTemplateDesc ]
                ]
            , a [ id "template-heros-journey", class "template-item", href <| Route.toString (Route.Import HerosJourney) ]
                [ div [ classList [ ( "template-thumbnail", True ) ] ] [ AntIcons.thunderboltOutlined [ width 48, height 48 ] ]
                , div [ class "template-title" ] [ text language HerosJourneyTemplate ]
                , div [ class "template-description" ]
                    [ text language HerosJourneyTemplateDesc ]
                ]
            ]
        ]
    ]
        |> modalWrapper msgs.modalClosed Nothing Nothing (tr language NewDocument)


viewWordCount :
    { activeCardId : String
    , workingTree : TreeStructure.Model
    , startingWordcount : Int
    , globalData : GlobalData
    }
    -> { modalClosed : msg }
    -> List (Html msg)
viewWordCount model msgs =
    let
        language =
            GlobalData.language model.globalData

        stats =
            getStats model

        current =
            stats.documentWords

        session =
            current - model.startingWordcount
    in
    [ div [ id "word-count-table" ]
        [ div [ class "word-count-column" ]
            [ span [] [ text language (WordCountCard stats.cardWords) ]
            , span [] [ text language (WordCountSubtree stats.subtreeWords) ]
            , span [] [ text language (WordCountGroup stats.groupWords) ]
            , span [] [ text language (WordCountColumn stats.columnWords) ]
            , span [] [ text language (WordCountSession session) ]
            , span [] [ text language (WordCountTotal current) ]
            ]
        , div [ class "word-count-column" ]
            [ span [] [ text language (CharacterCountCard stats.cardChars) ]
            , span [] [ text language (CharacterCountSubtree stats.subtreeChars) ]
            , span [] [ text language (CharacterCountGroup stats.groupChars) ]
            , span [] [ text language (CharacterCountColumn stats.columnChars) ]
            , span [] [ text language (CharacterCountTotal stats.documentChars) ]
            ]
        ]
    , span [ style "text-align" "center" ] [ text language (WordCountTotalCards stats.cards) ]
    ]
        |> modalWrapper msgs.modalClosed Nothing Nothing "Word & Character Counts"



-- DOCUMENT


viewSearchField : (String -> msg) -> { m | viewState : ViewState, globalData : GlobalData } -> Html msg
viewSearchField searchFieldMsg { viewState, globalData } =
    let
        language =
            GlobalData.language globalData

        maybeSearchIcon =
            if viewState.searchField == Nothing then
                Icon.search (defaultOptions |> Icon.color "#445" |> Icon.size 12)

            else
                emptyText
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


viewShortcuts :
    { toggledShortcutTray : msg, tooltipRequested : String -> TooltipPosition -> TranslationId -> msg, tooltipClosed : msg }
    -> Language
    -> Bool
    -> Bool
    -> Children
    -> TextCursorInfo
    -> ViewMode
    -> List (Html msg)
viewShortcuts msgs lang isOpen isMac children textCursorInfo viewMode =
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
                emptyText

        addInsteadOfSplit =
            textCursorInfo.position == End || textCursorInfo.position == Empty

        spanSplit key descAdd descSplit =
            if addInsteadOfSplit then
                shortcutSpan [ NoTr ctrlOrCmd, NoTr key ] descAdd

            else
                shortcutSpan [ NoTr ctrlOrCmd, NoTr key ] descSplit

        splitChild =
            spanSplit "L" AddChildAction SplitChildAction

        splitBelow =
            spanSplit "J" AddBelowAction SplitBelowAction

        splitAbove =
            spanSplit "K" AddAboveAction SplitUpwardAction

        shortcutSpanEnabled enabled keys desc =
            let
                keySpans =
                    keys
                        |> List.map (\k -> span [ class "shortcut-key" ] [ text lang k ])
            in
            span
                [ classList [ ( "disabled", not enabled ) ] ]
                (keySpans
                    ++ [ textNoTr (" " ++ tr lang desc) ]
                )

        shortcutSpan =
            shortcutSpanEnabled True

        formattingSpan markup =
            span [] [ pre [ class "formatting-text" ] [ text lang markup ] ]

        ctrlOrCmd =
            ctrlOrCmdText isMac
    in
    if isOpen then
        let
            iconColor =
                Icon.color "#445"
        in
        case viewMode of
            Normal ->
                [ div
                    [ id "shortcuts-tray", classList [ ( "open", isOpen ) ], onClick msgs.toggledShortcutTray ]
                    [ div [ id "shortcuts" ]
                        [ h3 [] [ text lang KeyboardShortcuts ]
                        , h5 [] [ text lang EditCards ]
                        , shortcutSpan [ EnterKey ] EnterAction
                        , shortcutSpan [ ShiftKey, EnterKey ] EditFullscreenAction
                        , viewIfNotOnly <| h5 [] [ text lang Navigate ]
                        , viewIfNotOnly <| shortcutSpan [ NoTr "↑", NoTr "↓", NoTr "←", NoTr "→" ] ArrowsAction
                        , h5 [] [ text lang AddNewCards ]
                        , shortcutSpan [ NoTr ctrlOrCmd, NoTr "→" ] AddChildAction
                        , shortcutSpan [ NoTr ctrlOrCmd, NoTr "↓" ] AddBelowAction
                        , shortcutSpan [ NoTr ctrlOrCmd, NoTr "↑" ] AddAboveAction
                        , viewIfNotOnly <| h5 [] [ text lang MoveAndDelete ]
                        , viewIfNotOnly <| shortcutSpan [ AltKey, ArrowKeys ] MoveAction
                        , viewIfNotOnly <| shortcutSpan [ NoTr ctrlOrCmd, Backspace ] DeleteAction
                        , viewIfNotOnly <| h5 [] [ text lang MergeCards ]
                        , viewIfNotOnly <| shortcutSpan [ NoTr ctrlOrCmd, ShiftKey, NoTr "↓" ] MergeDownAction
                        , viewIfNotOnly <| shortcutSpan [ NoTr ctrlOrCmd, ShiftKey, NoTr "↑" ] MergeUpAction
                        , hr [] []
                        , h5 [] [ text lang OtherShortcuts ]
                        , shortcutSpan [ NoTr "w" ] DisplayWordCounts
                        , shortcutSpan [ NoTr ctrlOrCmd, NoTr "O" ] QuickDocumentSwitcher
                        ]
                    ]
                ]

            _ ->
                [ div
                    [ id "shortcuts-tray", classList [ ( "open", isOpen ) ], onClick msgs.toggledShortcutTray ]
                    [ div [ id "shortcuts" ]
                        [ h3 [] [ text lang KeyboardShortcuts ]
                        , h3 [] [ text lang EditMode ]
                        , h5 [] [ text lang SaveOrCancelChanges ]
                        , shortcutSpan [ NoTr ctrlOrCmd, EnterKey ] ToSaveChanges
                        , shortcutSpan [ EscKey ] ToCancelChanges
                        , if addInsteadOfSplit then
                            h5 [] [ text lang AddNewCards ]

                          else
                            h5 [] [ text lang SplitAtCursor ]
                        , splitChild
                        , splitBelow
                        , splitAbove
                        , h5 [] [ text lang Formatting ]
                        , shortcutSpanEnabled isTextSelected [ NoTr ctrlOrCmd, NoTr "B" ] ForBold
                        , shortcutSpanEnabled isTextSelected [ NoTr ctrlOrCmd, NoTr "I" ] ForItalic
                        , shortcutSpan [ AltKey, ParenNumber ] SetHeadingLevel
                        , formattingSpan FormattingTitle
                        , formattingSpan FormattingList
                        , formattingSpan FormattingLink
                        , span [ class "markdown-guide" ]
                            [ a [ href "http://commonmark.org/help", target "_blank" ]
                                [ text lang FormattingGuide
                                , span [ class "icon-container" ] [ Icon.linkExternal (defaultOptions |> iconColor |> Icon.size 14) ]
                                ]
                            ]
                        ]
                    ]
                ]

    else
        [ div
            [ id "shortcuts-tray"
            , onClick msgs.toggledShortcutTray
            , onMouseEnter <| msgs.tooltipRequested "shortcuts-tray" LeftTooltip KeyboardShortcuts
            , onMouseLeave msgs.tooltipClosed
            ]
            [ keyboardIconSvg 24 ]
        ]



-- Word count


type alias Stats =
    { cardWords : Int
    , cardChars : Int
    , subtreeWords : Int
    , subtreeChars : Int
    , groupWords : Int
    , groupChars : Int
    , columnWords : Int
    , columnChars : Int
    , documentWords : Int
    , documentChars : Int
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


viewTooltip : Language -> ( Element, TooltipPosition, TranslationId ) -> Html msg
viewTooltip lang ( el, tipPos, content ) =
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

                AboveTooltip ->
                    [ style "left" <| ((el.element.x + el.element.width * 0.5) |> String.fromFloat) ++ "px"
                    , style "top" <| ((el.element.y + 5) |> String.fromFloat) ++ "px"
                    , style "transform" "translate(-50%, calc(-100% - 10px))"
                    , class "tip-above"
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
                    , style "transform" "translateX(calc(-100% + 10px))"
                    , class "tip-below-left"
                    ]
    in
    div ([ class "tooltip" ] ++ posAttributes)
        [ text lang content, div [ class "tooltip-arrow" ] [] ]


getStats : { m | activeCardId : String, workingTree : TreeStructure.Model } -> Stats
getStats { activeCardId, workingTree } =
    let
        tree =
            workingTree.tree

        cardsTotal =
            (workingTree.tree
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

        ( cardWords, cardChars ) =
            count currentTree.content

        ( subtreeWords, subtreeChars ) =
            count (treeToMarkdownString False currentTree)
                |> Tuple.mapBoth (\w -> w + cardWords) (\c -> c + cardChars)

        ( groupWords, groupChars ) =
            currentGroup
                |> List.map .content
                |> String.join "\n\n"
                |> count

        ( columnWords, columnChars ) =
            getColumn (getDepth 0 tree activeCardId) tree
                -- Maybe (List (List Tree))
                |> Maybe.withDefault [ [] ]
                |> List.concat
                |> List.map .content
                |> String.join "\n\n"
                |> count

        ( treeWords, treeChars ) =
            count (treeToMarkdownString False tree)
    in
    Stats
        cardWords
        cardChars
        subtreeWords
        subtreeChars
        groupWords
        groupChars
        columnWords
        columnChars
        treeWords
        treeChars
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


count : String -> ( Int, Int )
count str =
    let
        punctuation =
            Regex.fromString "[!@#$%^&*():;\"',.]+"
                |> Maybe.withDefault Regex.never

        wordCounts =
            str
                |> String.toLower
                |> replace punctuation (\_ -> "")
                |> String.words
                |> List.filter ((/=) "")
                |> List.length

        charCounts =
            str
                |> String.toList
                |> List.length
    in
    ( wordCounts, charCounts )


viewConflict : Language -> (String -> Selection -> String -> msg) -> (String -> msg) -> Conflict -> Html msg
viewConflict language setSelectionMsg resolveMsg { id, opA, opB, selection, resolved } =
    let
        withManual cardId oursElement theirsElement =
            li
                []
                [ fieldset []
                    [ radio (setSelectionMsg id Original cardId) (selection == Original) emptyText
                    , radio (setSelectionMsg id Ours cardId) (selection == Ours) oursElement
                    , radio (setSelectionMsg id Theirs cardId) (selection == Theirs) theirsElement
                    , radio (setSelectionMsg id Manual cardId) (selection == Manual) emptyText
                    , label []
                        [ input [ checked resolved, type_ "checkbox", onClick (resolveMsg id) ] []
                        , emptyText
                        ]
                    ]
                ]

        withoutManual cardIdA cardIdB =
            li
                []
                [ fieldset []
                    [ radio (setSelectionMsg id Original "") (selection == Original) emptyText
                    , radio (setSelectionMsg id Ours cardIdA) (selection == Ours) (text language <| NoTr <| ("Ours:" ++ (opString opA |> String.left 3)))
                    , radio (setSelectionMsg id Theirs cardIdB) (selection == Theirs) (text language <| NoTr <| ("Theirs:" ++ (opString opB |> String.left 3)))
                    , label []
                        [ input [ checked resolved, type_ "checkbox", onClick (resolveMsg id) ] []
                        , emptyText
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
                        [ emptyText ]
                    , div [ class "row flex-row" ]
                        [ div
                            [ classList [ ( "option", True ), ( "selected", selection == Ours ) ]
                            , onClick (setSelectionMsg id Ours cardId)
                            ]
                            [ emptyText
                            , ul [ class "changelist" ] ourChanges
                            ]
                        , div
                            [ classList [ ( "option", True ), ( "selected", selection == Theirs ) ]
                            , onClick (setSelectionMsg id Theirs cardId)
                            ]
                            [ emptyText
                            , ul [ class "changelist" ] theirChanges
                            ]
                        ]
                    , div
                        [ classList [ ( "row option", True ), ( "selected", selection == Manual ) ]
                        , onClick (setSelectionMsg id Manual cardId)
                        ]
                        [ emptyText ]
                    ]
                , button [ onClick (resolveMsg id) ] [ emptyText ]
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
                                        Just (li [] [ ins [ class "diff" ] [ textNoTr s ] ])

                                    Removed s ->
                                        Just (li [] [ del [ class "diff" ] [ textNoTr s ] ])
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


keyboardIconSvg w =
    svg [ version "1.1", viewBox "0 0 172 172", width w ] [ g [ fill "none", Svg.Attributes.fillRule "nonzero", stroke "none", strokeWidth "1", strokeLinecap "butt", strokeLinejoin "miter", strokeMiterlimit "10", strokeDasharray "", strokeDashoffset "0", fontFamily "none", fontWeight "none", fontSize "none", textAnchor "none", Svg.Attributes.style "mix-blend-mode: normal" ] [ Svg.path [ d "M0,172v-172h172v172z", fill "none" ] [], g [ id "original-icon", fill "#000000" ] [ Svg.path [ d "M16.125,32.25c-8.86035,0 -16.125,7.26465 -16.125,16.125v64.5c0,8.86035 7.26465,16.125 16.125,16.125h129c8.86035,0 16.125,-7.26465 16.125,-16.125v-64.5c0,-8.86035 -7.26465,-16.125 -16.125,-16.125zM16.125,43h129c3.02344,0 5.375,2.35156 5.375,5.375v64.5c0,3.02344 -2.35156,5.375 -5.375,5.375h-129c-3.02344,0 -5.375,-2.35156 -5.375,-5.375v-64.5c0,-3.02344 2.35156,-5.375 5.375,-5.375zM21.5,53.75v10.75h10.75v-10.75zM43,53.75v10.75h10.75v-10.75zM64.5,53.75v10.75h10.75v-10.75zM86,53.75v10.75h10.75v-10.75zM107.5,53.75v10.75h10.75v-10.75zM129,53.75v10.75h10.75v-10.75zM21.5,75.25v10.75h10.75v-10.75zM43,75.25v10.75h10.75v-10.75zM64.5,75.25v10.75h10.75v-10.75zM86,75.25v10.75h10.75v-10.75zM107.5,75.25v10.75h10.75v-10.75zM129,75.25v10.75h10.75v-10.75zM53.75,96.75v10.75h53.75v-10.75zM21.5,96.83399v10.79199h21.5v-10.79199zM118.41797,96.83399v10.79199h21.5v-10.79199z" ] [] ] ] ]


fillet posStr =
    svg [ Svg.Attributes.class "fillet", Svg.Attributes.class posStr, preserveAspectRatio "none", viewBox "0 0 30 30" ]
        [ g [] [ Svg.path [ d "M 30 0 A 30 30 0 0 1 0 30 L 30 30 L 30 0 z " ] [] ] ]
