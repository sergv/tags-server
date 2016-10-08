----------------------------------------------------------------------------
-- |
-- Module      :  Server.Tags.AnalyzeHeader
-- Copyright   :  (c) Sergey Vinokurov 2016
-- License     :  BSD3-style (see LICENSE)
--
-- Maintainer  :  serg.foo@gmail.com
-- Created     :  Thursday, 22 September 2016
-- Stability   :
-- Portability :
--
--
----------------------------------------------------------------------------

{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE PatternSynonyms     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ViewPatterns        #-}

module Haskell.Language.Server.Tags.AnalyzeHeader
  ( analyzeHeader
  ) where

import Control.Arrow (first)
import Control.Monad.Except
import Control.Monad.Trans.Maybe
import Data.Foldable (toList)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import Data.Map (Map)
import qualified Data.Map as M
import Data.Monoid
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Text.PrettyPrint.Leijen.Text as PP

import Token (Pos(..), TokenVal(..), Token, posFile, posLine, unLine, TokenVal, PragmaType(..))
import FastTags (stripNewlines, UnstrippedTokens(..))

import Control.Monad.Logging
import Data.KeyMap (KeyMap)
import qualified Data.KeyMap as KM
import Data.SubkeyMap (SubkeyMap)
import qualified Data.SubkeyMap as SubkeyMap
import Data.Symbols
import Haskell.Language.Server.Tags.Types
import Text.PrettyPrint.Leijen.Text.Utils

analyzeHeader
  :: (MonadError Doc m, MonadLog m)
  => [Token]
  -> m (Maybe UnresolvedModuleHeader, [Token])
analyzeHeader ts =
  -- logDebug $ "[analyzeHeader] ts =" <+> pretty (Tokens ts)
  case dropWhile ((/= KWModule) . valOf) ts of
    Pos _ KWModule :
      (dropNLs -> Pos _ (T modName) :
        (break ((== KWWhere) . valOf) . dropNLs -> (exportList, Pos _ KWWhere : body))) -> do
      (importSpecs, importQualifiers, body') <- analyzeImports SubkeyMap.empty mempty body
      exports                                <- analyzeExports importQualifiers exportList
      let header = ModuleHeader
            { mhModName          = mkModuleName modName
            , mhImports          = importSpecs
            , mhImportQualifiers = importQualifiers
            , mhExports          = exports
            }
      pure (Just header, body')
      -- No header present.
    _ -> pure (Nothing, ts)

pattern PImport       <- Pos _ KWImport
pattern PPattern      <- Pos _ (T "pattern")
pattern PModule       <- Pos _ KWModule
pattern PString       <- Pos _ String
pattern PQualified    <- Pos _ (T "qualified")
pattern PName name    <- Pos _ (T name)
pattern PAs           <- Pos _ (T "as")
pattern PHiding       <- Pos _ (T "hiding")
pattern PLParen       <- Pos _ LParen
pattern PRParen       <- Pos _ RParen
pattern PComma        <- Pos _ Comma
pattern PSourcePragma <- Pos _ (Pragma SourcePragma)

analyzeImports
  :: forall m. (MonadError Doc m, MonadLog m)
  => SubkeyMap ImportKey (NonEmpty UnresolvedImportSpec)
  -> Map ImportQualifier (NonEmpty ModuleName)
  -> [Token]
  -> m ( SubkeyMap ImportKey (NonEmpty UnresolvedImportSpec)
       , Map ImportQualifier (NonEmpty ModuleName)
       , [Token]
       )
analyzeImports imports qualifiers ts = do
  res <- runMaybeT $ do
    (ts', importTarget)      <- case dropNLs ts of
                                  PImport : (d -> PSourcePragma : rest) -> pure (rest, HsBootModule)
                                  PImport :                       rest  -> pure (rest, VanillaModule)
                                  _                                     -> mzero
    ts''                     <- case dropNLs ts' of
                                  PString : rest -> pure rest
                                  rest           -> pure rest
    (ts''', isQualified)     <- case dropNLs ts'' of
                                  PQualified : rest -> pure (rest, True)
                                  rest              -> pure (rest, False)
    (ts'''', name, qualName) <- case dropNLs ts''' of
                                  PName name : (d -> PAs : (d -> PName qualName : rest)) -> pure (rest, name, Just qualName)
                                  PName name :                                    rest   -> pure (rest, name, Nothing)
                                  _                                                      -> mzero
    let qualType = case (isQualified, qualName) of
                     (True,  Nothing)        -> Qualified $ mkQual name
                     (True,  Just qualName') -> Qualified $ mkQual qualName'
                     (False, Nothing)        -> Unqualified
                     (False, Just qualName') -> BothQualifiedAndUnqualified $ mkQual qualName'
    pure (name, qualType, importTarget, ts'''')
  case res of
    Nothing                                 -> pure (imports, qualifiers, ts)
    Just (name, qualType, importTarget, ts) -> add name qualType importTarget ts

  -- p <- case dropNLs ts of
  --        -- Vanilla imports
  --        PImport :                       (d ->                 PQualified : rest)   -> pure (rest, True, False)
  --        PImport :                                                          rest    -> pure (rest, False, False)
  --        PImport : (d -> PSourcePragma : (d ->                 PQualified : rest))  -> pure (rest, True, True)
  --        PImport : (d -> PSourcePragma :                                    rest)   -> pure (rest, False, True)
  --        -- Package-qualified imports
  --        PImport :                       (d -> PString : (d -> PQualified : rest))  -> pure (rest, True, False)
  --        PImport :                       (d -> PString :                    rest)   -> pure (rest, False, False)
  --        PImport : (d -> PSourcePragma : (d -> PString : (d -> PQualified : rest))) -> pure (rest, True, True)
  --        PImport : (d -> PSourcePragma : (d -> PString :                    rest))  -> pure (rest, False, True)
  --        _                                                                          -> mzero
  -- case p of
  --   -- Imports ended
  --   Nothing                                  -> pure (imports, qualifiers, ts)
  --   Just (rest, isQualified, isHsBootImport) -> do
  --     case dropNLs rest of
  --       PName name : (d -> PAs : (d -> PName qualName : rest)) -> undefined
  --       PName name : (d ->                              rest)  -> undefined

  -- case dropNLs ts of
  --   -- Vanilla imports
  --   PImport : (d ->                 PQualified : (d -> PName name : (d -> PAs : (d -> PName qualName : rest))))  -> add name (Qualified $ mkQual qualName) rest
  --   PImport : (d ->                 PQualified : (d -> PName name :                                    rest))    -> add name (Qualified $ mkQual name) rest
  --   PImport : (d ->                                    PName name : (d -> PAs : (d -> PName qualName : rest)))   -> add name (BothQualifiedAndUnqualified $ mkQual qualName) rest
  --   PImport : (d ->                                    PName name :                                    rest)     -> add name Unqualified rest
  --   -- Package-qualified imports
  --   PImport : (d -> PString : (d -> PQualified : (d -> PName name : (d -> PAs : (d -> PName qualName : rest))))) -> add name (Qualified $ mkQual qualName) rest
  --   PImport : (d -> PString : (d -> PQualified : (d -> PName name :                                    rest)))   -> add name (Qualified $ mkQual name) rest
  --   PImport : (d -> PString : (d ->                    PName name : (d -> PAs : (d -> PName qualName : rest))))  -> add name (BothQualifiedAndUnqualified $ mkQual qualName) rest
  --   PImport : (d -> PString : (d ->                    PName name :                                    rest))    -> add name Unqualified rest
  --   _ -> pure (imports, qualifiers, ts)
  where
    d      = dropNLs
    mkQual = mkImportQualifier . mkModuleName
    add
      :: Text
      -> ImportQualification
      -> ImportTarget
      -> [Token]
      -> m ( SubkeyMap ImportKey (NonEmpty UnresolvedImportSpec)
           , Map ImportQualifier (NonEmpty ModuleName)
           , [Token]
           )
    add name qual importTarget toks = do
      (importList, toks') <- analyzeImportList toks
      let spec     = mkNewSpec importList
          imports' = SubkeyMap.alter' (upd spec) (ImportKey importTarget modName) imports
      analyzeImports imports' qualifiers' toks'
      where
        modName :: ModuleName
        modName = mkModuleName name
        qualifiers' :: Map ImportQualifier (NonEmpty ModuleName)
        qualifiers' = case getQualifier qual of
                        Just q  -> M.alter (Just . upd modName) q qualifiers
                        Nothing -> qualifiers
        mkNewSpec :: Maybe UnresolvedImportList -> UnresolvedImportSpec
        mkNewSpec importList = ImportSpec
          { ispecImportKey     = ImportKey
              { ikModuleName   = modName
              , ikImportTarget = importTarget
              }
          , ispecQualification = qual
          , ispecImportList    = importList
          }
        upd :: forall a. a -> Maybe (NonEmpty a) -> NonEmpty a
        upd x prev =
          case prev of
            Nothing    -> x :| []
            Just specs -> NE.cons x specs
    -- Analyze comma-separated list of entries like
    -- - Foo
    -- - Foo(Bar, Baz)
    -- - Quux(..)
    analyzeImportList :: [Token] -> m (Maybe (ImportList ()), [Token])
    analyzeImportList toks =
      case dropNLs toks of
        []                                    -> pure (Nothing, toks)
        PHiding : (dropNLs -> PLParen : rest) -> first Just <$> findImportListEntries Hidden mempty (dropNLs rest)
        PLParen : rest                        -> first Just <$> findImportListEntries Imported mempty (dropNLs rest)
        _                                     -> pure (Nothing, toks)
      where
        findImportListEntries
          :: ImportType
          -> KeyMap (EntryWithChildren UnqualifiedSymbolName)
          -> [Token]
          -> m (ImportList (), [Token])
        findImportListEntries importType acc toks =
          case dropNLs toks of
            []             -> pure (importList, [])
            PRParen : rest -> pure (importList, rest)
            toks'          -> do
              (descr, name, rest) <- case toks' of
                                       PLParen : PName name : PRParen : rest ->
                                         return ("operator in import list", name, rest)
                                       PName name : rest                     ->
                                         return ("name in import list", name, rest)
                                       rest                                  ->
                                         throwError $ "Unrecognized shape of import list:" <+> pretty (Tokens rest)
              (children, rest')   <- analyzeChildren descr $ dropNLs rest
              name'               <- mkUnqualName name
              let newEntry = EntryWithChildren name' children
              findImportListEntries importType (KM.insert newEntry acc) $ dropComma rest'
          where
            importList :: ImportList ()
            importList = ImportList
              { ilEntries       = acc
              , ilImportType    = importType
              , ilImportedNames = ()
              }
        mkUnqualName :: Text -> m UnqualifiedSymbolName
        mkUnqualName name =
          case mkUnqualifiedSymbolName (mkSymbolName name) of
            Nothing    ->
              throwError $ "Invalid qualified entry on import list:" <+> docFromText name
            Just name' -> return name'

analyzeExports
  :: forall m. (MonadError Doc m, MonadLog m)
  => Map ImportQualifier (NonEmpty ModuleName)
  -> [Token]
  -> m (Maybe ModuleExports)
analyzeExports importQualifiers ts =
  case stripNewlines $ UnstrippedTokens ts of
    []            -> pure Nothing
    PLParen : rest -> Just <$> go mempty mempty rest
    toks          ->
      throwError $ "Unrecognized shape of export list:" <+> pretty (Tokens toks)
  where
    -- Analyze comma-separated list of entries like
    -- - Foo
    -- - Foo(Bar, Baz)
    -- - Quux(..)
    -- - pattern PFoo
    -- - module Data.Foo.Bar
    go :: KeyMap (EntryWithChildren SymbolName)
       -> Set ModuleName
       -> [Token]
       -> m ModuleExports
    go entries reexports = \case
      []                                    -> pure exports
      [PRParen]                             -> pure exports
      PLParen : PName name : PRParen : rest -> do
        (children, rest') <- analyzeChildren "operator in export list" rest
        let newEntry = EntryWithChildren (mkSymbolName name) children
        consumeComma (KM.insert newEntry entries) reexports rest'
      PName name : rest                     -> do
        (children, rest') <- analyzeChildren "name in export list" rest
        let newEntry = EntryWithChildren (mkSymbolName name) children
        consumeComma (KM.insert newEntry entries) reexports rest'
      PPattern : PName name : rest          ->
        consumeComma (KM.insert newEntry entries) reexports rest
        where
          newEntry = mkEntryWithoutChildren $ mkSymbolName name
      PModule  : PName name : rest          ->
        consumeComma entries (newReexports <> reexports) rest
        where
          modName = mkModuleName name
          newReexports :: Set ModuleName
          newReexports
            = S.fromList
            $ toList
            $ M.findWithDefault (modName :| []) (mkImportQualifier modName) importQualifiers
      toks                                  ->
        throwError $ "Unrecognized export list structure:" <+> pretty (Tokens toks)
      where
        exports = ModuleExports
          { meExportedEntries    = entries
          , meReexports          = reexports
          , meHasWildcardExports = getAny $ foldMap exportsAllChildren entries
          }
        exportsAllChildren (EntryWithChildren _ visibility) =
          maybe mempty isExportAllChildren visibility
          where
            isExportAllChildren VisibleAllChildren          = Any True
            isExportAllChildren (VisibleSpecificChildren _) = mempty
    -- Continue parsing by consuming comma delimiter.
    consumeComma
      :: KeyMap (EntryWithChildren SymbolName)
      -> Set ModuleName
      -> [Token]
      -> m ModuleExports
    consumeComma entries reexports = go entries reexports . dropComma

analyzeChildren
  :: forall m. (MonadError Doc m, MonadLog m)
  => Doc -> [Token] -> m (Maybe ChildrenVisibility, [Token])
analyzeChildren listType = \case
  []                                     ->           pure (Nothing, [])
  toks@(PComma : _)                                -> pure (Nothing, toks)
  toks@(PRParen : _)                               -> pure (Nothing, toks)
  -- PLParen : PDot : PDot : PRParen : rest -> pure (Just VisibleAllChildren, rest)
  PLParen : PName ".." : PRParen : rest            -> pure (Just VisibleAllChildren, rest)
  PLParen : PRParen : rest                         -> pure (Nothing, rest)
  PLParen : rest@(PName _ : _)                     -> do
    -- (children, rest') <- analyzeCommaSeparatedNameList rest
    (children, rest') <- extractChildren mempty rest
    pure (Just $ VisibleSpecificChildren children, rest')
  PLParen : rest@(PLParen : PName _ : PRParen : _) -> do
    -- (children, rest') <- analyzeCommaSeparatedNameList rest
    (children, rest') <- extractChildren mempty rest
    pure (Just $ VisibleSpecificChildren children, rest')
  toks ->
    throwError $ "Cannot handle children of" <+> listType <+> ":" <+> pretty (Tokens toks)
  where
    extractChildren
      :: Set UnqualifiedSymbolName
      -> [Token]
      -> m (Set UnqualifiedSymbolName, [Token])
    extractChildren names = \case
      []             -> pure (names, [])
      PRParen : rest -> pure (names, rest)
      PName name : rest
        | Just name' <- mkUnqualifiedSymbolName $ mkSymbolName name ->
          extractChildren (S.insert name' names) $ dropComma rest
      PLParen : PName name : PRParen : rest
        | Just name' <- mkUnqualifiedSymbolName $ mkSymbolName name ->
          extractChildren (S.insert name' names) $ dropComma rest
      toks           ->
        throwError $ "Unrecognized children list structure:" <+> pretty (Tokens toks)

newtype Tokens = Tokens [Token]

instance Pretty Tokens where
  pretty (Tokens [])       = "[]"
  pretty (Tokens ts@(t : _)) =
    ppDict "Tokens"
      [ "file"   :-> showDoc (posFile $ posOf t)
      , "tokens" :-> ppList (map ppTokenVal ts)
      ]
    where
      ppTokenVal :: Pos TokenVal -> Doc
      ppTokenVal (Pos pos tag) =
        pretty (unLine (posLine pos)) <> PP.colon <> showDoc tag

-- | Drop prefix of newlines.
dropNLs :: [Token] -> [Token]
dropNLs (Pos _ (Newline _) : ts) = dropNLs ts
dropNLs ts                       = ts

dropComma :: [Token] -> [Token]
dropComma (Pos _ Comma : ts) = ts
dropComma ts                 = ts
