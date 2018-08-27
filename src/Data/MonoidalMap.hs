----------------------------------------------------------------------------
-- |
-- Module      :  Data.MonoidalMap
-- Copyright   :  (c) Sergey Vinokurov 2016
-- License     :  BSD3-style (see LICENSE)
-- Maintainer  :  serg.foo@gmail.com
-- Created     :  Wednesday, 28 September 2016
----------------------------------------------------------------------------

module Data.MonoidalMap
  ( MonoidalMap
  , singleton
  , unMonoidalMap
  ) where

import Data.Map (Map)
import qualified Data.Map as M

newtype MonoidalMap k v = MonoidalMap { unMonoidalMap :: Map k v }
  deriving (Eq, Ord, Show)

instance (Ord k, Semigroup v) => Semigroup (MonoidalMap k v) where
  (<>) (MonoidalMap x) (MonoidalMap y) = MonoidalMap $ M.unionWith (<>) x y

instance (Ord k, Semigroup v) => Monoid (MonoidalMap k v) where
  mempty = MonoidalMap mempty
  mappend = (<>)

singleton :: k -> v -> MonoidalMap k v
singleton k v = MonoidalMap $ M.singleton k v
