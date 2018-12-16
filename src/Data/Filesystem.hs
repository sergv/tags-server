----------------------------------------------------------------------------
-- |
-- Module      :  Data.Filesystem
-- Copyright   :  (c) Sergey Vinokurov 2018
-- License     :  BSD3-style (see LICENSE)
-- Maintainer  :  serg.foo@gmail.com
----------------------------------------------------------------------------

{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE CPP                 #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE MultiWayIf          #-}
{-# LANGUAGE Rank2Types          #-}
{-# LANGUAGE ScopedTypeVariables #-}

#ifdef mingw32_HOST_OS
#define WINDOWS 1
#endif

module Data.Filesystem
  ( findRecurCollect
  , findRecursive
  ) where

import Control.Concurrent.Async.Lifted
import Control.Concurrent.STM
import Control.Concurrent.STM.TMQueue
import Control.Monad.Base
import Control.Monad.Catch
import Control.Monad.Trans.Control

import Data.Foldable.Ext
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.NBSem
import Data.Path
import Data.Semigroup as Semigroup
import Data.Set (Set)
import qualified Data.Set as S
import qualified Data.Streaming.Filesystem as Streaming
import qualified Data.Text as T
import GHC.Conc (getNumCapabilities)
import GHC.Stack.Ext (WithCallStack)
import qualified System.FilePath as FilePath

#ifdef WINDOWS
#else
import qualified Control.Exception as Exception
import System.Posix.Files as Posix
#endif

import Data.Path.Internal
import Data.CompiledRegex

{-# INLINE findRecursive #-}
findRecursive
  :: forall a m. (WithCallStack, MonadBaseControl IO m, MonadMask m)
  => Int                             -- ^ Extra search threads to run in parallel
  -> (FullPath 'Dir -> Bool)         -- ^ Whether to visit directory
  -> (FullPath 'File -> m (Maybe a)) -- ^ What to do with a file
  -> (FullPath 'Dir  -> m (Maybe a)) -- ^ What to do with a directory
  -> (a -> m ())                     -- ^ Consume output
  -> Set (FullPath 'Dir)             -- ^ Dirs to search non-recursively
  -> Set (FullPath 'Dir)             -- ^ Dirs to search recursively
  -> m ()
findRecursive extraJobs dirVisitPred filePred dirPred consume shallowDirs recursiveDirs = do
  sem <- newNBSem extraJobs
  findRecursive' sem
  where
    findRecursive' :: NBSem -> m ()
    findRecursive' sem =
      foldr
        (goDirRec (const False))
        (foldr
          (goDirRec dirVisitPred)
          (pure ())
          recursiveDirs)
        shallowDirs
      where
        goDirRec :: (FullPath 'Dir -> Bool) -> FullPath 'Dir -> m () -> m ()
        goDirRec dirPred' = goDirAsyncOrSync . (T.unpack . unFullPath)
          where
            goDirAsyncOrSync :: FilePath -> m () -> m ()
            goDirAsyncOrSync root next = do
              acquired <- tryAcquireNBSem sem
              if acquired
              then
                withAsync (goDir root `finally` releaseNBSem sem) $ \yAsync ->
                  next *> wait yAsync
              else goDir root *> next
            goDir :: FilePath -> m ()
            goDir root =
              bracket
                (liftBase (Streaming.openDirStream root))
                (liftBase . Streaming.closeDirStream)
                goDirStream
              where
                goDirStream :: Streaming.DirStream -> m ()
                goDirStream stream = go
                  where
                    go :: m ()
                    go = do
                      x <- liftBase $ Streaming.readDirStream stream
                      for_ x $ \y -> do
                        let y' :: FilePath
                            y' = root FilePath.</> y
                        let doFile =
                              (filePred y'' >>= traverse_ consume) *> go
                              where
                                y'' :: FullPath 'File
                                y'' = FullPath $ T.pack y'
                            doDir =
                              if dirPred' y''
                              then
                                (dirPred y'' >>= traverse_ consume) *> goDirAsyncOrSync y' go
                              else go
                              where
                                y'' :: FullPath 'Dir
                                y'' = FullPath $ T.pack y'
#ifdef WINDOWS
                        ft <- liftBase $ Streaming.getFileType y'
                        case ft of
                          Streaming.FTOther        -> go
                          Streaming.FTFile         -> doFile
                          Streaming.FTFileSym      -> doFile
                          Streaming.FTDirectory    -> doDir
                          Streaming.FTDirectorySym -> doDir
#else
                        status <- liftBase $ Posix.getSymbolicLinkStatus y'
                        if | Posix.isRegularFile  status -> doFile
                           | Posix.isDirectory    status -> doDir
                           | Posix.isSymbolicLink status -> do
                             status' <- liftBase $ Exception.try $ Posix.getFileStatus y'
                             case status' of
                               Left (_ :: Exception.IOException) -> go
                               Right status''
                                 | Posix.isRegularFile status'' -> doFile
                                 | Posix.isDirectory   status'' -> doDir
                                 | otherwise                    -> go
                           | otherwise                   -> go
#endif


{-# INLINABLE findRecurCollect #-}
findRecurCollect
  :: forall k v m. (WithCallStack, Ord k, Semigroup v, MonadBaseControl IO m, MonadMask m)
  => Set (BaseName 'Dir)
  -> CompiledRegex
  -> Set (FullPath 'Dir)
  -> Set (FullPath 'Dir)
  -> (FullPath 'File -> m (Maybe (k, v)))
  -> m (Map k v)
findRecurCollect ignoredDirs ignoredGlobsRE shallowPaths recursivePaths f = do
  n       <- liftBase getNumCapabilities
  results <- liftBase newTMQueueIO
  let collect :: (k, v) -> m ()
      collect = liftBase . atomically . writeTMQueue results

      shouldVisit :: FullPath 'Dir -> Bool
      shouldVisit path =
        takeFileName path `S.notMember` ignoredDirs &&
        not (reMatches ignoredGlobsRE (unFullPath path))

      consume :: Map k v -> IO (Map k v)
      consume !xs = do
        res <- atomically $ readTMQueue results
        case res of
          Nothing     -> pure xs
          Just (k, v) -> consume $ M.insertWith (Semigroup.<>) k v xs

      f' :: FullPath 'File -> m (Maybe (k, v))
      f' path
        | reMatches ignoredGlobsRE (unFullPath path)
        = pure Nothing
        | otherwise
        = f path

      -- Reserve 1 capability for synchronous processing
      extraJobs = n - 1

      doFind =
        findRecursive extraJobs shouldVisit f' (const (pure Nothing)) collect shallowPaths recursivePaths
  withAsync (doFind `finally` liftBase (atomically (closeTMQueue results))) $ \searchAsync ->
    liftBase (consume M.empty) <* (wait searchAsync :: m ())
