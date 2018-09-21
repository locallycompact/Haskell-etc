{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Etc.Internal.Resolver where

import RIO
import qualified RIO.Map as Map

import           Etc.Internal.Config           (Config)
import           Etc.Internal.Resolver.Default (defaultResolver)
import           Etc.Internal.Resolver.Types
import qualified Etc.Internal.Spec.Types       as Spec

resolveConfig :: (MonadUnliftIO m) => [(Text, Spec.CustomType)] -> Spec.ConfigSpec -> [Resolver m] -> m Config
resolveConfig customTypesList spec resolvers =
    resolveAll
  where
    customTypes =
      Map.fromList customTypesList

    indexedResolvers =
      -- defaultResolver will always be the one that has the least precedence
      zip [(0 :: Int) ..] $ reverse (defaultResolver : resolvers)

    runIndexedResolver priorityIndex resolver =
      runResolver resolver priorityIndex customTypes spec

    resolveAll =
      mconcat <$> mapM (uncurry runIndexedResolver) indexedResolvers
