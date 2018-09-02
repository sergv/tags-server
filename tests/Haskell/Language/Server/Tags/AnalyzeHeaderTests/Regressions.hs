----------------------------------------------------------------------------
-- |
-- Module      :  Haskell.Language.Server.Tags.AnalyzeHeaderTests.Regressions
-- Copyright   :  (c) Sergey Vinokurov 2016
-- License     :  BSD3-style (see LICENSE)
-- Maintainer  :  serg.foo@gmail.com
-- Created     :  Friday, 14 October 2016
----------------------------------------------------------------------------

{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}

module Haskell.Language.Server.Tags.AnalyzeHeaderTests.Regressions
  ( aesonHeaderTest
  , unixCompatHeaderTest
  ) where

import Control.Arrow ((&&&))
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import qualified Data.Map as M
import qualified Data.Set as S
import qualified Data.Text as T

import Data.Symbols
import Haskell.Language.Server.Tags.Types.Imports
import Haskell.Language.Server.Tags.Types.Modules

import qualified Data.KeyMap as KM
import qualified Data.SubkeyMap as SubkeyMap
import TestUtils
import qualified Text.RawString.QQ as QQ

type Test = TestCase T.Text UnresolvedModuleHeader

aesonHeaderTest :: Test
aesonHeaderTest = TestCase
  { testName       = "Data.Aeson.TH header"
  , input          = aesonHeader
  , expectedResult = ModuleHeader
      { mhModName          = mkModuleName "Data.Aeson.TH"
      , mhExports          = SpecificExports ModuleExports
          { meExportedEntries    = KM.fromList $
              [ EntryWithChildren
                  { entryName               = mkSymbolName name
                  , entryChildrenVisibility = Just VisibleAllChildren
                  }
              | name <- ["Options", "SumEncoding"]
              ] ++
              [ EntryWithChildren
                  { entryName               = mkSymbolName name
                  , entryChildrenVisibility = Nothing
                  }
              | name <- [ "defaultOptions", "defaultTaggedObject", "deriveJSON"
                        , "deriveToJSON", "deriveFromJSON", "mkToJSON"
                        , "mkToEncoding", "mkParseJSON"
                        ]
              ]
          , meReexports          = mempty
          , meHasWildcardExports = True
          }
      , mhImportQualifiers = M.fromList
          [ (mkImportQualifier (mkModuleName short), mkModuleName <$> long)
          | (short, long) <-
              [ ("A",   neSingleton "Data.Aeson")
              , ("E",   "Data.Aeson.Encode.Functions" :| ["Data.Aeson.Encode.Builder"])
              , ("H",   neSingleton "Data.HashMap.Strict")
              , ("Set", neSingleton "Data.Set")
              , ("T",   neSingleton "Data.Text")
              , ("V",   neSingleton "Data.Vector")
              , ("VM",  neSingleton "Data.Vector.Mutable")
              ]
          ]
      , mhImports          = SubkeyMap.fromList $ map (ispecImportKey . NE.head &&& id)
          [ neSingleton ImportSpec
              { ispecImportKey = ImportKey
                  { ikImportTarget = VanillaModule
                  , ikModuleName   = mkModuleName modName
                  }
              , ispecQualification = qual
              , ispecImportList    = flip fmap imported $ \entries -> ImportList
                  { ilEntries       = KM.fromList entries
                  , ilImportType    = Imported
                  }
              , ispecImportedNames = ()
              }
          | (modName, qual, imported) <-
              [ ( "Control.Applicative"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName name
                        , entryChildrenVisibility = Nothing
                        }
                    | name <- ["pure", "<$>", "<*>"]
                    ]
                )
              , ( "Control.Monad"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName name
                        , entryChildrenVisibility = Nothing
                        }
                    | name <- ["return", "mapM", "liftM2", "fail"]
                    ]
                )
              , ( "Control.Monad"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName name
                        , entryChildrenVisibility = Nothing
                        }
                    | name <- ["return", "mapM", "liftM2", "fail", "join"]
                    ]
                )
              , ( "Data.Aeson"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName name
                        , entryChildrenVisibility = Nothing
                        }
                    | name <- [ "toJSON", "Object", ".=", ".:", ".:?", "ToJSON"
                              , "toEncoding", "toJSON", "FromJSON", "parseJSON"
                              ]
                    ]
                )
              , ( "Data.Aeson.Types"
                , Unqualified
                , Just $
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName name
                        , entryChildrenVisibility = Nothing
                        }
                    | name <- ["Parser", "defaultOptions", "defaultTaggedObject"]
                    ] ++
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName name
                        , entryChildrenVisibility = Just VisibleAllChildren
                        }
                    | name <- ["Value", "Options", "SumEncoding"]
                    ]
                )
              , ( "Data.Aeson.Types.Internal"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName "Encoding"
                        , entryChildrenVisibility = Just VisibleAllChildren
                        }
                    ]
                )
              , ( "Data.Bool"
                , Unqualified
                , Just $
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName "Bool"
                        , entryChildrenVisibility = Just $ VisibleSpecificChildren $ S.fromList
                            [ mkUnqualSymName "False"
                            , mkUnqualSymName "True"
                            ]
                        }
                    ] ++
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName name
                        , entryChildrenVisibility = Nothing
                        }
                    | name <- ["otherwise", "&&", "not"]
                    ]
                )
              , ( "Data.Either"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName "Either"
                        , entryChildrenVisibility = Just $ VisibleSpecificChildren $ S.fromList
                            [ mkUnqualSymName "Left"
                            , mkUnqualSymName "Right"
                            ]
                        }
                    ]
                )
              , ( "Data.Eq"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName "=="
                        , entryChildrenVisibility = Nothing
                        }
                    ]
                )
              , ( "Data.Function"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName name
                        , entryChildrenVisibility = Nothing
                        }
                    | name <- ["$", ".", "flip"]
                    ]
                )
              , ( "Data.Functor"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName "fmap"
                        , entryChildrenVisibility = Nothing
                        }
                    ]
                )
              , ( "Data.Int"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName "Int"
                        , entryChildrenVisibility = Nothing
                        }
                    ]
                )
              , ( "Data.List"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName name
                        , entryChildrenVisibility = Nothing
                        }
                    | name <- [ "++", "all", "any", "filter", "find", "foldl"
                              , "foldl'", "genericLength", "intercalate"
                              , "intersperse", "length", "map", "partition"
                              , "zip"
                              ]
                    ]
                )
              , ( "Data.Maybe"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName "Maybe"
                        , entryChildrenVisibility = Just $ VisibleSpecificChildren $ S.fromList
                            [ mkUnqualSymName "Nothing"
                            , mkUnqualSymName "Just"
                            ]
                        }
                    , EntryWithChildren
                        { entryName               = mkUnqualSymName "catMaybes"
                        , entryChildrenVisibility = Nothing
                        }
                    ]
                )
              , ( "Data.Monoid"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName name
                        , entryChildrenVisibility = Nothing
                        }
                    | name <- ["<>", "mconcat"]
                    ]
                )
              , ( "Language.Haskell.TH"
                , Unqualified
                , Nothing
                )
              , ( "Language.Haskell.TH.Syntax"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName "VarStrictType"
                        , entryChildrenVisibility = Nothing
                        }
                    ]
                )
              , ( "Prelude"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName name
                        , entryChildrenVisibility = Nothing
                        }
                    | name <- [ "String", "-", "Integer", "error", "foldr1"
                              , "fromIntegral", "snd", "uncurry"
                              ]
                    ]
                )
              , ( "Prelude"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName "drop"
                        , entryChildrenVisibility = Nothing
                        }
                    ]
                )
              , ( "Text.Printf"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName "printf"
                        , entryChildrenVisibility = Nothing
                        }
                    ]
                )
              , ( "Text.Show"
                , Unqualified
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName "show"
                        , entryChildrenVisibility = Nothing
                        }
                    ]
                )
              , ( "Data.Aeson"
                , Qualified $ mkImportQualifier $ mkModuleName "A"
                , Nothing
                )
              , ( "Data.Aeson.Encode.Builder"
                , Qualified $ mkImportQualifier $ mkModuleName "E"
                , Nothing
                )
              , ( "Data.Aeson.Encode.Functions"
                , Qualified $ mkImportQualifier $ mkModuleName "E"
                , Nothing
                )
              , ( "Data.HashMap.Strict"
                , Qualified $ mkImportQualifier $ mkModuleName "H"
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName name
                        , entryChildrenVisibility = Nothing
                        }
                    | name <- ["lookup", "toList"]
                    ]
                )
              , ( "Data.Set"
                , Qualified $ mkImportQualifier $ mkModuleName "Set"
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName name
                        , entryChildrenVisibility = Nothing
                        }
                    | name <- [ "Set", "empty", "singleton", "size", "union"
                              , "unions"
                              ]
                    ]
                )
              , ( "Data.Text"
                , Qualified $ mkImportQualifier $ mkModuleName "T"
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName name
                        , entryChildrenVisibility = Nothing
                        }
                    | name <- ["Text", "pack", "unpack"]
                    ]
                )
              , ( "Data.Vector"
                , Qualified $ mkImportQualifier $ mkModuleName "V"
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName name
                        , entryChildrenVisibility = Nothing
                        }
                    | name <- [ "unsafeIndex", "null", "length", "create"
                              , "fromList"
                              ]
                    ]
                )
              , ( "Data.Vector.Mutable"
                , Qualified $ mkImportQualifier $ mkModuleName "VM"
                , Just
                    [ EntryWithChildren
                        { entryName               = mkUnqualSymName name
                        , entryChildrenVisibility = Nothing
                        }
                    | name <- ["unsafeNew", "unsafeWrite"]
                    ]
                )
              ]
          ]
      }
  }

unixCompatHeaderTest :: Test
unixCompatHeaderTest = TestCase
  { testName       = "System.PosixCompat.Types"
  , input          = unixCompatHeader
  , expectedResult = ModuleHeader
      { mhModName          = mkModuleName "System.PosixCompat.Types"
      , mhExports          = SpecificExports ModuleExports
          { meExportedEntries    = KM.fromList $
              [ EntryWithChildren
                  { entryName               = mkSymbolName name
                  , entryChildrenVisibility = Nothing
                  }
              | name <- ["FileID", "UserID", "GroupID", "LinkCount"]
              ]
          , meReexports          = S.fromList
              [ mkModuleName "System.Posix.Types"
              ]
          , meHasWildcardExports = False
          }
      , mhImportQualifiers = M.fromList
          [ (mkImportQualifier (mkModuleName short), mkModuleName <$> long)
          | (short, long) <-
              [ ("AllPosixTypesButFileID", neSingleton "System.Posix.Types")
              ]
          ]
      , mhImports          = SubkeyMap.fromList $ map (ispecImportKey . NE.head &&& id)
          [ neSingleton ImportSpec
              { ispecImportKey = ImportKey
                  { ikImportTarget = VanillaModule
                  , ikModuleName   = mkModuleName "System.Posix.Types"
                  }
              , ispecQualification =
                  BothQualifiedAndUnqualified $
                  mkImportQualifier $
                  mkModuleName "AllPosixTypesButFileID"
              , ispecImportList    = Just $ ImportList
                  { ilEntries    = KM.fromList
                      [ EntryWithChildren
                          { entryName               = mkUnqualSymName "FileID"
                          , entryChildrenVisibility = Nothing
                          }
                      ]
                  , ilImportType = Hidden
                  }
              , ispecImportedNames = ()
              }
          ]
      }
  }

-- Raw headers

aesonHeader :: T.Text
aesonHeader = [QQ.r|
{-# LANGUAGE CPP                  #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE IncoherentInstances  #-}
{-# LANGUAGE NamedFieldPuns       #-}
{-# LANGUAGE NoImplicitPrelude    #-}
{-# LANGUAGE OverlappingInstances #-}
{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE UndecidableInstances #-}

{-|
Module:      Data.Aeson.TH
Copyright:   (c) 2011-2015 Bryan O'Sullivan
             (c) 2011 MailRank, Inc.
License:     Apache
Stability:   experimental
Portability: portable

Functions to mechanically derive 'ToJSON' and 'FromJSON' instances. Note that
you need to enable the @TemplateHaskell@ language extension in order to use this
module.

...

Please note that you can derive instances for tuples using the following syntax:

@
-- FromJSON and ToJSON instances for 4-tuples.
$('deriveJSON' 'defaultOptions' ''(,,,))
@

-}

module Data.Aeson.TH
    ( -- * Encoding configuration
      Options(..), SumEncoding(..), defaultOptions, defaultTaggedObject

     -- * FromJSON and ToJSON derivation
    , deriveJSON

    , deriveToJSON
    , deriveFromJSON

    , mkToJSON
    , mkToEncoding
    , mkParseJSON
    ) where

import Control.Applicative ( pure, (<$>), (<*>) )
import Control.Monad       ( return, mapM, liftM2, fail )
import Data.Aeson ( toJSON, Object, (.=), (.:), (.:?)
                  , ToJSON, toEncoding, toJSON
                  , FromJSON, parseJSON
                  )
import Data.Aeson.Types ( Value(..), Parser
                        , Options(..)
                        , SumEncoding(..)
                        , defaultOptions
                        , defaultTaggedObject
                        )
import Data.Aeson.Types.Internal (Encoding(..))
import Control.Monad       ( return, mapM, liftM2, fail, join )
import Data.Bool           ( Bool(False, True), otherwise, (&&), not )
import Data.Either         ( Either(Left, Right) )
import Data.Eq             ( (==) )
import Data.Function       ( ($), (.), flip )
import Data.Functor        ( fmap )
import Data.Int            ( Int )
import Data.List           ( (++), all, any, filter, find, foldl, foldl'
                           , genericLength , intercalate , intersperse, length, map
                           , partition, zip
                           )
import Data.Maybe          ( Maybe(Nothing, Just), catMaybes )
import Data.Monoid         ( (<>), mconcat )
import Language.Haskell.TH
import Language.Haskell.TH.Syntax ( VarStrictType )
import Prelude             ( String, (-), Integer, error, foldr1, fromIntegral
                           , snd, uncurry
                           )
#if MIN_VERSION_template_haskell(2,8,0) && __GLASGOW_HASKELL__ < 710
import Prelude             ( drop )
#endif
import Text.Printf         ( printf )
import Text.Show           ( show )
import qualified Data.Aeson as A
import qualified Data.Aeson.Encode.Builder as E
import qualified Data.Aeson.Encode.Functions as E
import qualified Data.HashMap.Strict as H ( lookup, toList )
#if MIN_VERSION_template_haskell(2,8,0) && __GLASGOW_HASKELL__ < 710
import qualified Data.Set as Set ( Set, empty, singleton, size, union, unions )
#endif
import qualified Data.Text as T ( Text, pack, unpack )
import qualified Data.Vector as V ( unsafeIndex, null, length, create, fromList )
import qualified Data.Vector.Mutable as VM ( unsafeNew, unsafeWrite )
|]

unixCompatHeader :: T.Text
unixCompatHeader = [QQ.r|
{-# LANGUAGE CPP #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

{-|
This module re-exports the types from @System.Posix.Types@ on all platforms.

On Windows 'UserID', 'GroupID' and 'LinkCount' are missing, so they are
redefined by this module.
-}
module System.PosixCompat.Types (
#ifdef mingw32_HOST_OS
     module AllPosixTypesButFileID
    , FileID
    , UserID
    , GroupID
    , LinkCount
#else
     module System.Posix.Types
#endif
    ) where

#ifdef mingw32_HOST_OS
-- Since CIno (FileID's underlying type) reflects <sys/type.h> ino_t,
-- which mingw defines as short int (int16), it must be overriden to
-- match the size of windows fileIndex (word64).
import System.Posix.Types as AllPosixTypesButFileID hiding (FileID)
|]
