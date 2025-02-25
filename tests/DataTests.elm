module DataTests exposing (..)

import Doc.Data as Data exposing (CardOp_tests_only(..), Card_tests_only, Delta_tests_only, SaveError_tests_only(..), cardOpConvert, localSave, model_tests_only, saveErrors_tests_only, toDelta_tests_only, toSave_tests_only)
import Expect exposing (Expectation)
import Json.Encode as Enc
import Test exposing (..)
import Types exposing (CardTreeOp(..))
import UpdatedAt


suite : Test
suite =
    describe "Data"
        [ describe "localSave"
            [ test "CTIns to empty model" <|
                \_ ->
                    localSave "treeId" (CTIns "someid" "new content" Nothing 0) Data.emptyCardBased
                        |> expectEqualJSON
                            (toSave
                                { toAdd =
                                    [ card "someid" "treeId" "new content" Nothing 0.0 False False () ]
                                , toMarkSynced = []
                                , toMarkDeleted = []
                                , toRemove = []
                                }
                            )
            , test "CTIns to model with existing card" <|
                \_ ->
                    let
                        data =
                            d
                                [ card "otherId"
                                    "treeId"
                                    ""
                                    Nothing
                                    0.0
                                    False
                                    True
                                    (u 12345 0 "afe223")
                                ]
                                Nothing
                    in
                    localSave "treeId" (CTIns "someid" "new content" Nothing 1) data
                        |> expectEqualJSON
                            (toSave
                                { toAdd =
                                    [ card "someid" "treeId" "new content" Nothing 1 False False () ]
                                , toMarkSynced = []
                                , toMarkDeleted = []
                                , toRemove = []
                                }
                            )
            , test "CTUpd existing card" <|
                \_ ->
                    let
                        data =
                            d
                                [ card "someid"
                                    "treeId"
                                    "old content"
                                    Nothing
                                    0.0
                                    False
                                    True
                                    (u 12345 0 "afe223")
                                ]
                                Nothing
                    in
                    localSave "treeId" (CTUpd "someid" "new content") data
                        |> expectEqualJSON
                            (toSave
                                { toAdd =
                                    [ card "someid"
                                        "treeId"
                                        "new content"
                                        Nothing
                                        0.0
                                        False
                                        False
                                        ()
                                    ]
                                , toMarkSynced = []
                                , toMarkDeleted = []
                                , toRemove = []
                                }
                            )
            , test "CTUpd non-existing card should return an error" <|
                \_ ->
                    let
                        data =
                            d
                                [ card "otherId"
                                    "treeId"
                                    ""
                                    Nothing
                                    0.0
                                    False
                                    True
                                    (u 12345 0 "afe223")
                                ]
                                Nothing
                    in
                    localSave "treeId" (CTUpd "someid" "new content") data
                        |> expectEqualJSON
                            (saveErrors [ CardDoesNotExist_tests_only { id = "someid", src = "CTUpd toAdd_ Nothing" } ])
            , test "CTUpd when multiple versions of the card exist" <|
                \_ ->
                    let
                        data =
                            d
                                [ card "someId"
                                    "treeId"
                                    "second content"
                                    Nothing
                                    0.0
                                    False
                                    True
                                    (u 12346 0 "afe223")
                                , card "someId"
                                    "treeId"
                                    "first content"
                                    Nothing
                                    0.0
                                    False
                                    False
                                    (u 12345 0 "afe223")
                                ]
                                Nothing
                    in
                    localSave "treeId" (CTUpd "someId" "third content") data
                        |> expectEqualJSON
                            (toSave
                                { toAdd = [ card "someId" "treeId" "third content" Nothing 0.0 False False () ]
                                , toMarkSynced = []
                                , toMarkDeleted = []
                                , toRemove = []
                                }
                            )
            , test "CTUpd when empty conflicts exist" <|
                \_ ->
                    let
                        data =
                            d
                                [ card "someId"
                                    "treeId"
                                    "second content"
                                    Nothing
                                    0.0
                                    False
                                    True
                                    (u 12346 0 "afe223")
                                ]
                                (Just { ours = [], theirs = [], original = [] })
                    in
                    localSave "treeId" (CTUpd "someId" "third content") data
                        |> expectEqualJSON
                            (toSave
                                { toAdd = [ card "someId" "treeId" "third content" Nothing 0.0 False False () ]
                                , toMarkSynced = []
                                , toMarkDeleted = []
                                , toRemove = []
                                }
                            )
            , test "CTMrg when one of the cards doesn't exist" <|
                \_ ->
                    let
                        data =
                            d
                                [ card "otherId"
                                    "treeId"
                                    ""
                                    Nothing
                                    0.0
                                    False
                                    True
                                    (u 12345 0 "afe223")
                                ]
                                Nothing
                    in
                    localSave "treeId" (CTMrg "someid" "otherId" False) data
                        |> expectEqualJSON
                            (saveErrors [ CardDoesNotExist_tests_only { id = "someid", src = "CTMrg currCard_ Nothing" } ])
            ]
        , describe "toDelta"
            [ test "parent insertion order bug" <|
                \_ ->
                    let
                        cards =
                            [ card "RMTI" "treeId" "" Nothing 0.0 False False (u 310153 0 "fe2e9")
                            , card "3NJe9" "treeId" "" (Just "RMTI") 0.0 False False (u 313820 0 "fe2e9")
                            , card "ZchLy" "treeId" "" (Just "3NJe9") 0.0 False False (u 314495 0 "fe2e9")
                            , card "3NJe9" "treeId" "gsaa" (Just "RMTI") 0.0 False False (u 314495 1 "fe2e9")
                            ]
                    in
                    toDelta "treeId" cards
                        |> Expect.equal
                            [ delta "RMTI"
                                "treeId"
                                (u 310153 0 "fe2e9")
                                [ cOp <| InsOp_t { id = "RMTI", content = "", parentId = Nothing, position = 0.0 } ]
                            , delta "3NJe9"
                                "treeId"
                                (u 313820 0 "fe2e9")
                                [ cOp <| InsOp_t { id = "3NJe9", content = "", parentId = Just "RMTI", position = 0.0 } ]
                            , delta "ZchLy"
                                "treeId"
                                (u 314495 0 "fe2e9")
                                [ cOp <| InsOp_t { id = "ZchLy", content = "", parentId = Just "3NJe9", position = 0.0 } ]
                            , delta "3NJe9"
                                "treeId"
                                (u 314495 1 "fe2e9")
                                [ cOp <| UpdOp_t { content = "gsaa", expectedVersion = u 313820 0 "fe2e9" } ]
                            ]
            ]
        ]



-- HELPERS


expectEqualJSON : Enc.Value -> Enc.Value -> Expectation
expectEqualJSON a b =
    Expect.equal (Enc.encode 0 a) (Enc.encode 0 b)


card =
    Card_tests_only


toSave =
    toSave_tests_only


saveErrors =
    saveErrors_tests_only


d =
    model_tests_only


u a b c =
    UpdatedAt.fromParts a b c



-- delta tests


delta =
    Delta_tests_only


toDelta =
    toDelta_tests_only


cOp =
    cardOpConvert
