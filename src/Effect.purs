-- | This module provides the `Effect` type, which is used to represent
-- | _native_ effects. The `Effect` type provides a typed API for effectful
-- | computations, while at the same time generating efficient JavaScript.
-- |
-- | As in Haskell, values in PureScript do not have side-effects by default.
-- | This module provides the standard type PureScript uses to handle "native"
-- | effects, i.e. effects which are provided by the runtime system, and which
-- | cannot be emulated by pure functions. Some examples of native effects are:
-- |
-- | * Console IO
-- | * Random number generation
-- | * Exceptions
-- | * Reading/writing mutable state
-- |
-- | And in the browser:
-- |
-- | * DOM manipulation
-- | * XMLHttpRequest / AJAX calls
-- | * Interacting with a websocket
-- | * Writing/reading to/from local storage
-- |
-- | All of these things may be represented in PureScript by the `Effect` type.
-- | A value of the type `Effect a` represents a computation which may perform
-- | some native effects, and which produces a value of the type `a` once it
-- | finishes. For example, the module `Effect.Random` from `purescript-random`
-- | exports a value `random`, whose type is `Effect Number`. When run, this
-- | effect produces a random number between 0 and 1. To give another example,
-- | the module `Effect.Console` exports a function `log`, whose type is
-- | `String -> Effect Unit`. This function takes a string and produces an
-- | effect which, when run, prints the provided string to the console.
-- |
-- | ```purescript
-- | module RandomExample where
-- | import Prelude
-- | import Effect (Effect)
-- | import Effect.Random (random)
-- | import Effect.Console (log)
-- |
-- | printRandom :: Effect Unit
-- | printRandom = do
-- |   n <- random
-- |   log (show n)
-- | ```
-- |
-- | In this example, `printRandom` is an effect which generates a random
-- | number between 0 and 1 and prints it to the console. You can test it out
-- | in the repl:
-- |
-- | ```
-- | > import RandomExample
-- | > printRandom
-- | 0.71831842260513870
-- | unit
-- | ```
-- |
-- | The `unit` is there because all effects must produce a value. When there
-- | is nothing useful to return, we usually use the type `Unit`, which has
-- | just one value: `unit`.
-- |
-- | #### Effects and Purity
-- |
-- | Note that using `Effect` does not compromise the purity of your program.
-- | Functions which make use of `Effect` are still pure, in the sense that
-- | all functions will return the same outputs given the same inputs.
-- |
-- | This is enabled by having the `Effect` type denote _values_ which can be
-- | run to produce native effects; an `Effect a` is a computation which has
-- | not yet necessarily been performed. In fact, there is no way of "running"
-- | an `Effect` manually; we cannot provide a (safe) function of the type
-- | `forall a. Effect a -> a`, because such a function would violate purity;
-- | it could produce different outputs given the same input. (Note that there
-- | is actually such a function in the module `Effect.Unsafe`, but it is best
-- | avoided outside of exceptional circumstances.)
-- |
-- | Instead, the recommended way of "running" an effect is to include it as
-- | part of your program's `main` value.
-- |
-- | A consequence of being able to represent native effects purely using
-- | `Effect` is that you can construct and pass `Effect` values around your
-- | programs freely. For example, we can write functions which can decide
-- | whether to run a given effect just once, many times, or not at all:
-- |
-- | ```purescript
-- | -- | Runs an effect three times, provided that the given condition is
-- | -- | true.
-- | thriceIf :: Boolean -> Effect Unit -> Effect Unit
-- | thriceIf cond effect =
-- |   if cond
-- |     then do
-- |       effect
-- |       effect
-- |       effect
-- |     else
-- |       pure unit
-- | ```
-- |
-- | #### Using Effects via the Foreign Function Interface
-- |
-- | A computation of type `Effect a` is implemented in JavaScript as a
-- | zero-argument function whose body is expected to perform its side-effects
-- | before finally returning its result. For example, suppose we wanted a
-- | computation which would increment a global counter and return the new
-- | result each time it was run. We can implement this as follows:
-- |
-- | ```purescript
-- | -- Counter.purs
-- | foreign import incrCounter :: Effect Int
-- | ```
-- |
-- | and in the corresponding JavaScript module:
-- |
-- | ```javascript
-- | // Counter.js
-- | exports.incrCounter = function() {
-- |   if (!window.globalCounter) {
-- |     window.globalCounter = 0;
-- |   }
-- |   return ++window.globalCounter;
-- | }
-- | ```
-- |
-- | For more information about the FFI (Foreign Function Interface), see
-- | the [documentation repository](https://github.com/purescript/documentation).
-- |
-- | #### The Effect type is Magic
-- |
-- | The PureScript compiler has special support for the `Effect` monad.
-- | Ordinarily, a chain of monadic binds might result in poor performance when
-- | executed. However, the compiler can generate code for the `Effect` monad
-- | without explicit calls to the monadic bind function `>>=`.
-- |
-- | Take the random number generation example from above. When compiled, the
-- | compiler produces the following JavaScript:
-- |
-- | ```javascript
-- | var printRandom = function __do() {
-- |     var $0 = Effect_Random.random();
-- |     return Effect_Console.log(Data_Show.show(Data_Show.showNumber)($0))();
-- | };
-- | ```
-- |
-- | whereas a more naive compiler might, for instance, produce:
-- | ```javascript
-- | var printRandom = Control_Bind.bind(Effect.bindEffect)(Effect_Random.random)(function ($0) {
-- |     return Effect_Console.log(Data_Show.show(Data_Show.showNumber)($0));
-- | });
-- | ```
-- |
-- | While this is a small improvement, the benefit is greater when using
-- | multiple nested calls to `>>=`.
module Effect
  ( Effect
  , untilE, whileE, forE, foreachE
  ) where

import Prelude

import Control.Apply (lift2)

-- | A native effect. The type parameter denotes the return type of running the
-- | effect, that is, an `Effect Int` is a possibly-effectful computation which
-- | eventually produces a value of the type `Int` when it finishes.
foreign import data Effect :: Type -> Type

instance functorEffect :: Functor Effect where
  map = liftA1

instance applyEffect :: Apply Effect where
  apply = ap

instance applicativeEffect :: Applicative Effect where
  pure = pureE

foreign import pureE :: forall a. a -> Effect a

instance bindEffect :: Bind Effect where
  bind = bindE

foreign import bindE :: forall a b. Effect a -> (a -> Effect b) -> Effect b

instance monadEffect :: Monad Effect

-- | The `Semigroup` instance for effects allows you to run two effects, one
-- | after the other, and then combine their results using the result type's
-- | `Semigroup` instance.
instance semigroupEffect :: Semigroup a => Semigroup (Effect a) where
  append = lift2 append

-- | If you have a `Monoid a` instance, then `mempty :: Effect a` is defined as
-- | `pure mempty`.
instance monoidEffect :: Monoid a => Monoid (Effect a) where
  mempty = pureE mempty

-- | Loop until a condition becomes `true`.
-- |
-- | `untilE b` is an effectful computation which repeatedly runs the effectful
-- | computation `b`, until its return value is `true`.
foreign import untilE :: Effect Boolean -> Effect Unit

-- | Loop while a condition is `true`.
-- |
-- | `whileE b m` is effectful computation which runs the effectful computation
-- | `b`. If its result is `true`, it runs the effectful computation `m` and
-- | loops. If not, the computation ends.
foreign import whileE :: forall a. Effect Boolean -> Effect a -> Effect Unit

-- | Loop over a consecutive collection of numbers.
-- |
-- | `forE lo hi f` runs the computation returned by the function `f` for each
-- | of the inputs between `lo` (inclusive) and `hi` (exclusive).
foreign import forE :: Int -> Int -> (Int -> Effect Unit) -> Effect Unit

-- | Loop over an array of values.
-- |
-- | `foreachE xs f` runs the computation returned by the function `f` for each
-- | of the inputs `xs`.
foreign import foreachE :: forall a. Array a -> (a -> Effect Unit) -> Effect Unit
