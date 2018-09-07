----------------------------------------------------------------------------
-- |
-- Module      :  Data.SubkeyMap
-- Copyright   :  (c) Sergey Vinokurov 2016
-- License     :  BSD3-style (see LICENSE)
-- Maintainer  :  serg.foo@gmail.com
-- Created     :  Saturday,  8 October 2016
----------------------------------------------------------------------------

{-# LANGUAGE DeriveFoldable      #-}
{-# LANGUAGE DeriveFunctor       #-}
{-# LANGUAGE DeriveTraversable   #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving  #-}
{-# LANGUAGE TypeFamilies        #-}

module Data.SubkeyMap
  ( SubkeyMap
  , HasSubkey(..)
  , empty
  , null
  , insert
  , insertWith
  , lookup
  , lookupSubkey
  , lookupSubkeyKeys
  , alter'
  , traverseWithKey
  , traverseMaybeWithKey
  , fromMap
  , fromList
  , fromFoldable
  , toList
  , toSubkeyList
  , toSubkeyKeyList
  , keys
  ) where

import Control.Arrow
import Control.Monad.State.Strict
import Data.Foldable (foldl')
import Data.Map (Map)
import qualified Data.Map as M
import Data.Semigroup
import Data.Set (Set)
import qualified Data.Set as S
import Prelude hiding (lookup, null)

class (Ord k, Ord (Subkey k)) => HasSubkey k where
  type Subkey k :: *
  getSubkey :: k -> Subkey k

-- | Map which can index same set of values by two keys. One key is the
-- main one (the bigger one), the second key is the subkey which is a projection
-- of the main key. -- Since it is a projection, it may reference several
-- values.
-- Deletions are not provided for the time being in order to simplify
-- impementation.
-- Invariant: both keys are kept in sync with each other.
data SubkeyMap k v = SubkeyMap
  { smMainMap :: !(Map k v)
  , smSubMap  :: !(Map (Subkey k) (Set k))
  } deriving (Functor, Foldable, Traversable)

deriving instance (Eq k,   Eq (Subkey k),   Eq v)   => Eq (SubkeyMap k v)
deriving instance (Ord k,  Ord (Subkey k),  Ord v)  => Ord (SubkeyMap k v)
deriving instance (Show k, Show (Subkey k), Show v) => Show (SubkeyMap k v)

instance (HasSubkey k, Semigroup v) => Semigroup (SubkeyMap k v) where
  SubkeyMap m1 s1 <> SubkeyMap m2 s2 = SubkeyMap
    { smMainMap = M.unionWith (<>) m1 m2
    , smSubMap  = M.unionWith (<>) s1 s2
    }

instance (HasSubkey k, Semigroup v) => Monoid (SubkeyMap k v) where
  mempty  = empty
  mappend = (<>)

empty :: SubkeyMap k v
empty = SubkeyMap
  { smMainMap = M.empty
  , smSubMap  = M.empty
  }

null :: SubkeyMap k v -> Bool
null = M.null . smMainMap

insert :: (HasSubkey k, Semigroup v) => k -> v -> SubkeyMap k v -> SubkeyMap k v
insert = insertWith (<>)

insertWith :: HasSubkey k => (v -> v -> v) -> k -> v -> SubkeyMap k v -> SubkeyMap k v
insertWith f k v SubkeyMap{smMainMap, smSubMap} = SubkeyMap
  { smMainMap = M.insertWith f k v smMainMap
  , smSubMap  = M.insertWith (<>) (getSubkey k) (S.singleton k) smSubMap
  }

lookup :: Ord k => k -> SubkeyMap k v -> Maybe v
lookup k = M.lookup k . smMainMap

lookupSubkey :: HasSubkey k => Subkey k -> SubkeyMap k v -> [v]
lookupSubkey k SubkeyMap{smMainMap, smSubMap} =
  case M.lookup k smSubMap of
    Nothing   -> []
    Just idxs -> smMainMap `indexBySet` idxs

-- | Find out which keys correspond to the given subkey.
lookupSubkeyKeys :: HasSubkey k => Subkey k -> SubkeyMap k v -> Maybe (Set k)
lookupSubkeyKeys k = M.lookup k . smSubMap

alter' :: HasSubkey k => (Maybe v -> v) -> k -> SubkeyMap k v -> SubkeyMap k v
alter' f k SubkeyMap{smMainMap, smSubMap} = SubkeyMap
  { smMainMap = M.alter (Just . f) k smMainMap
  , smSubMap  = M.insertWith (<>) (getSubkey k) (S.singleton k) smSubMap
  }

traverseWithKey :: Applicative f => (k -> v -> f v') -> SubkeyMap k v -> f (SubkeyMap k v')
traverseWithKey f sm@SubkeyMap{smMainMap} =
  (\smMainMap' -> sm { smMainMap = smMainMap' }) <$> M.traverseWithKey f smMainMap

traverseMaybeWithKey
  :: forall f k v v'. (Applicative f, HasSubkey k)
  => (k -> v -> f (Maybe v')) -> SubkeyMap k v -> f (SubkeyMap k v')
traverseMaybeWithKey f sm@SubkeyMap{smMainMap, smSubMap} =
  update <$> M.traverseMaybeWithKey f smMainMap
  where
    update :: Map k v' -> SubkeyMap k v'
    update smMainMap' = sm
      { smMainMap = smMainMap'
      , smSubMap  =
        -- Do the expensive update only if anything changed.
        if M.size smMainMap' == M.size smMainMap
        then smSubMap
        else (`S.intersection` ks) <$> M.restrictKeys smSubMap subkeys
      }
      where
        ks :: Set k
        ks = M.keysSet smMainMap'
        subkeys :: Set (Subkey k)
        subkeys = S.map getSubkey ks

fromMap :: HasSubkey k => Map k v -> SubkeyMap k v
fromMap m = SubkeyMap
  { smMainMap = m
  , smSubMap  = M.fromListWith (<>) $ map (getSubkey &&& S.singleton) $ M.keys m
  }

fromList :: (HasSubkey k, Semigroup v) => [(k, v)] -> SubkeyMap k v
fromList = fromFoldable

fromFoldable :: (Foldable f, HasSubkey k, Semigroup v) => f (k, v) -> SubkeyMap k v
fromFoldable = foldl' (\acc (k, v) -> insert k v acc) empty

toList :: SubkeyMap k v -> [(k, v)]
toList = M.toList . smMainMap

toSubkeyList :: Ord k => SubkeyMap k v -> [(Subkey k, [v])]
toSubkeyList SubkeyMap{smMainMap, smSubMap} =
  map (second (smMainMap `indexBySet`)) $ M.toList smSubMap

toSubkeyKeyList :: Ord k => SubkeyMap k v -> [(Subkey k, Set k)]
toSubkeyKeyList = M.toList . smSubMap

keys :: SubkeyMap k v -> [k]
keys = M.keys . smMainMap

-- Utils

indexBySet :: Ord k => Map k v -> Set k -> [v]
indexBySet m ixs = M.elems $ m `M.intersection` M.fromSet (const ()) ixs
