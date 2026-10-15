package com.morphlet.animation

import android.graphics.Rect
import android.view.View
import android.view.ViewGroup
import com.facebook.react.uimanager.ReactClippingViewGroup
import com.morphlet.animation.MorphletSpring.Companion.lerp
import kotlin.math.roundToInt

class MorphletLayoutAnimator(private val root: ViewGroup) {

  private data class TaggedFrame(val tag: Int, val frame: Rect)

  private val capturedFrames = HashMap<View, TaggedFrame>()
  private val targetFrames = HashMap<View, TaggedFrame>()
  private var spring: MorphletSpring? = null

  fun capture() {
    capturedFrames.clear()
    forEachDescendant(root) { view -> capturedFrames[view] = TaggedFrame(view.id, frameOf(view)) }
  }

  fun discard() {
    capturedFrames.clear()
  }

  fun animate(config: MorphletSpringConfig): Boolean {
    var moved = false
    forEachDescendant(root) { view ->
      val from = capturedFrames[view]?.takeIf { it.tag == view.id }?.frame
      if (from == null || frameOf(view) != from) moved = true
    }
    if (!moved) {
      capturedFrames.clear()
      return false
    }

    val transitions = HashMap<View, Pair<Rect, Rect>>()
    forEachDescendant(root) { view ->
      val from = capturedFrames[view]?.takeIf { it.tag == view.id }?.frame ?: return@forEachDescendant
      if (from.isEmpty) return@forEachDescendant
      val current = frameOf(view)
      val target = targetFrames[view]?.takeIf { it.tag == view.id }?.frame
      val to = if (current == from) target ?: current else current
      if (to != from) {
        transitions[view] = from to to
      }
    }
    capturedFrames.clear()
    if (transitions.isEmpty()) return false

    spring?.cancel()
    targetFrames.clear()
    transitions.forEach { (view, frames) ->
      targetFrames[view] = TaggedFrame(view.id, frames.second)
      apply(view, frames.first)
    }
    spring = MorphletSpring.start(
      config,
      onUpdate = { progress ->
        transitions.forEach { (view, frames) ->
          if (targetFrames[view]?.tag == view.id) {
            apply(view, frames.first, frames.second, progress)
          }
        }
      },
      onEnd = { finished ->
        if (finished) {
          targetFrames.clear()
          spring = null
        }
      },
    )
    return true
  }

  fun finish() {
    spring?.cancel()
    spring = null
    targetFrames.forEach { (view, target) -> if (target.tag == view.id) apply(view, target.frame) }
    targetFrames.clear()
  }

  private fun forEachDescendant(parent: ViewGroup, action: (View) -> Unit) {
    for (index in 0 until parent.childCount) {
      val child = parent.getChildAt(index)
      action(child)
      if (child is ViewGroup && child is ReactClippingViewGroup) {
        forEachDescendant(child, action)
      }
    }
  }

  private fun frameOf(view: View): Rect = Rect(view.left, view.top, view.right, view.bottom)

  private fun apply(view: View, frame: Rect) {
    view.layout(frame.left, frame.top, frame.right, frame.bottom)
  }

  private fun apply(view: View, from: Rect, to: Rect, progress: Float) {
    view.layout(
      lerp(from.left.toFloat(), to.left.toFloat(), progress).roundToInt(),
      lerp(from.top.toFloat(), to.top.toFloat(), progress).roundToInt(),
      lerp(from.right.toFloat(), to.right.toFloat(), progress).roundToInt(),
      lerp(from.bottom.toFloat(), to.bottom.toFloat(), progress).roundToInt(),
    )
  }
}
