{-# LANGUAGE RankNTypes #-}

module Lets.Lens where

import Control.Applicative(Applicative(..))
import Data.Foldable(Foldable(..))
import Data.Functor((<$>))
import Data.Monoid(Monoid(..))
import Data.Traversable(Traversable(..))
import Lets.Data

-- Let's remind ourselves of Traversable, noting Foldable and Functor.
--
-- class (Foldable t, Functor t) => Traversable t where
--   traverse ::
--     Applicative f => 
--     (a -> f b)
--     -> t a
--     -> f (t b)

-- | Observe that @fmap@ can be recovered from @traverse@ using @Identity@.
--
-- /Reminder:/ fmap :: Functor t => (a -> b) -> t a -> t b
fmapT ::
  Traversable t =>
  (a -> b)
  -> t a
  -> t b
fmapT f =
  getIdentity . traverse (Identity . f)

-- | Let's refactor out the call to @traverse@ as an argument to @fmapT@.
over :: 
  ((a -> Identity b) -> s -> Identity t)
  -> (a -> b)
  -> s
  -> t
over t f =
  getIdentity . t (Identity . f)

-- | Here is @fmapT@ again, passing @traverse@ to @over@.
fmapTAgain ::
  Traversable t =>
  (a -> b)
  -> t a
  -> t b
fmapTAgain =
  over traverse

-- | Let's create a type-alias for this type of function.
type Set s t a b =
  (a -> Identity b)
  -> s
  -> Identity t

-- | Let's write an inverse to @over@ that does the @Identity@ wrapping &
-- unwrapping.
sets ::
  ((a -> b) -> s -> t)
  -> Set s t a b  
sets t f =
  Identity . t (getIdentity . f)

mapped ::
  Functor f =>
  Set (f a) (f b) a b
mapped =
  sets fmap

set ::
  Set s t a b
  -> b
  -> s
  -> t
set s b =
  over s (const b)

----

-- | Observe that @fmap@ can be recovered from @traverse@ using @Identity@.
--
-- /Reminder:/ foldMap :: (Foldable t, Monoid b) => (a -> b) -> t a -> b
foldMapT ::
  (Traversable t, Monoid b) =>
  (a -> b)
  -> t a
  -> b
foldMapT f =
  getConst . traverse (Const . f)

-- | Let's refactor out the call to @traverse@ as an argument to @foldMapT@.
foldMapOf ::
  ((a -> Const r b) -> s -> Const r t)
  -> (a -> r)
  -> s
  -> r
foldMapOf t f =
  getConst . t (Const . f)

-- | Here is @foldMapT@ again, passing @traverse@ to @foldMapOf@.
foldMapTAgain ::
  (Traversable t, Monoid b) =>
  (a -> b)
  -> t a
  -> b
foldMapTAgain =
  foldMapOf traverse

-- | Let's create a type-alias for this type of function.
type Fold s t a b =
  forall r.
  Monoid r =>
  (a -> Const r b)
  -> s
  -> Const r t

-- | Let's write an inverse to @foldMapOf@ that does the @Const@ wrapping &
-- unwrapping.
folds ::
  ((a -> b) -> s -> t)
  -> (a -> Const b a)
  -> s
  -> Const t s
folds t f =
  Const . t (getConst . f)

folded ::
  Foldable f =>
  Fold (f a) (f a) a a
folded =
  folds foldMap

----

-- | @Get@ is like @Fold@, but without the @Monoid@ constraint.
type Get r s a =
  (a -> Const r a)
  -> s
  -> Const r s

get ::
  Get a s a
  -> s
  -> a
get t a =
  getConst (t Const a)

----

-- | Let's generalise @Identity@ and @Const r@ to any @Applicative@ instance.
type Traversal s t a b =
  forall f.
  Applicative f =>
  (a -> f b)
  -> s
  -> f t

-- | Traverse both sides of a pair.
both ::
  Traversal (a, a) (b, b) a b
both f (a, b) =
  (,) <$> f a <*> f b

-- | Traverse the left side of @Either@.
traverseLeft ::
  Traversal (Either a x) (Either b x) a b
traverseLeft f (Left a) =
  Left <$> f a
traverseLeft _ (Right x) =
  pure (Right x)

-- | Traverse the right side of @Either@.
traverseRight ::
  Traversal (Either x a) (Either x b) a b
traverseRight _ (Left x) =
  pure (Left x)
traverseRight f (Right a) =
  Right <$> f a

----

-- | @Const r@ is @Applicative@, if @Monoid r@, however, without the @Monoid@
-- constraint (as in @Get@), the only shared abstraction between @Identity@ and
-- @Const r@ is @Functor@.
--
-- Consequently, we arrive at our lens derivation:
type Lens s t a b =
  forall f.
  Functor f =>
  (a -> f b)
  -> s
  -> f t

----

-- | A profunctor is a binary functor, with the first argument in contravariant
-- (negative) position and the second argument in covariant (positive) position.
class Profunctor p where
  dimap ::
    (b -> a)
    -> (c -> d)
    -> p a c
    -> p b d

instance Profunctor (->) where
  dimap f g = \h -> g . h . f

instance Profunctor Tagged where
  dimap _ g (Tagged x) =
    Tagged (g x)

diswap ::
  Profunctor p =>
  p (Either a b) (Either c d)
  -> p (Either b a) (Either d c)
diswap =
  let swap = either Right Left 
  in dimap swap swap

-- | Map on left or right of @Either@. Only one of @left@ or @right@ needs to be
-- provided.
class Profunctor p => Choice p where
  left ::
    p a b
    -> p (Either a c) (Either b c)
  left =
    diswap . right

  right ::
    p a b
    -> p (Either c a) (Either c b)
  right =
    diswap . left

instance Choice (->) where
  left f =
    either (Left . f) Right
  right f =
    either Left (Right . f)

instance Choice Tagged where
  left (Tagged x) =
    Tagged (Left x)
  right (Tagged x) =
    Tagged (Right x)

----

-- | A prism is a less specific type of traversal.
type Prism s t a b =
  forall p f.
  (Choice p, Applicative f) =>
  p a (f b)
  -> p s (f t)

_Left ::
  Prism (Either a x) (Either b x) a b
_Left =
  dimap (either Right (Left . Right)) (either pure (fmap Left)) . right

_Right ::
  Prism (Either x a) (Either x b) a b 
_Right =
  dimap (either (Left . Left) Right) (either pure (fmap Right)) . right

prism ::
  (b -> t)
  -> (s -> Either t a)
  -> Prism s t a b
prism to fr =
  dimap fr (either pure (fmap to)) . right

_Just ::
  Prism (Maybe a) (Maybe b) a b
_Just =
  prism
    Just
    (maybe (Left Nothing) Right)

_Nothing ::
  Prism (Maybe a) (Maybe a) () ()
_Nothing =
  prism
    (\() -> Nothing)
    (maybe (Right ()) (Left . Just))
    
setP ::
  Prism s t a b
  -> s
  -> Either a t
setP p =
  p Left

getP ::
  Prism s t a b
  -> b
  -> t
getP p =
  getIdentity . getTagged . p . Tagged . Identity
