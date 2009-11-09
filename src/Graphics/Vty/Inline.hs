{-# LANGUAGE BangPatterns #-}
module Graphics.Vty.Inline ( module Graphics.Vty.Inline
                           )
    where

import Graphics.Vty.Attributes
import Graphics.Vty.DisplayAttributes
import Graphics.Vty.Terminal.Generic

import Control.Applicative
import Control.Monad.State.Strict
import Control.Monad.Trans

import Data.Bits ( (.&.), complement )
import Data.IORef
import Data.Monoid ( mappend )

type AttrChange v = State Attr v

back_color :: Color -> AttrChange ()
back_color c = modify $ flip mappend ( current_attr `with_back_color` c )

fore_color :: Color -> AttrChange ()
fore_color c = modify $ flip mappend ( current_attr `with_fore_color` c )

apply_style :: Style -> AttrChange ()
apply_style s = modify $ flip mappend ( current_attr `with_style` s )

remove_style :: Style -> AttrChange ()
remove_style s_mask = modify $ \attr -> 
    let style' = case attr_style attr of
                    Default -> error $ "Graphics.Vty.Inline: Cannot remove_style if apply_style never used."
                    KeepCurrent -> error $ "Graphics.Vty.Inline: Cannot remove_style if apply_style never used."
                    SetTo s -> s .&. complement s_mask
    in attr { attr_style = SetTo style' } 

put_default_attr :: ( Applicative m, MonadIO m ) => TerminalHandle -> m () 
put_default_attr t = do
    bounds <- display_bounds t
    d <- display_context t bounds
    marshall_to_terminal t ( default_attr_required_bytes d )
                           ( serialize_default_attr d )
    liftIO $ modifyIORef ( state_ref t ) $ \s -> s { known_fattr = Just $ FixedAttr default_style_mask Nothing Nothing }

put_attr_change :: ( Applicative m, MonadIO m ) => TerminalHandle -> AttrChange () -> m ()
put_attr_change t c = do
    bounds <- display_bounds t
    d <- display_context t bounds
    mfattr <- liftIO $ known_fattr <$> readIORef ( state_ref t )
    fattr <- case mfattr of
                Nothing -> do
                    marshall_to_terminal t (default_attr_required_bytes d) (serialize_default_attr d) 
                    return $ FixedAttr default_style_mask Nothing Nothing
                Just v -> return v
    let attr = execState c current_attr
        attr' = limit_attr_for_display d attr
        fattr' = fix_display_attr fattr attr'
        diffs = display_attr_diffs fattr fattr'
    marshall_to_terminal t ( attr_required_bytes d fattr attr' diffs )
                           ( serialize_set_attr d fattr attr' diffs )
    liftIO $ modifyIORef ( state_ref t ) $ \s -> s { known_fattr = Just fattr' }
