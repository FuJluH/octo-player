package app.winters.octo.desktop.perf

import androidx.compose.runtime.ExperimentalComposeRuntimeApi
import androidx.compose.runtime.RecomposeScope
import androidx.compose.runtime.Recomposer
import androidx.compose.runtime.tooling.CompositionObserver
import androidx.compose.runtime.tooling.CompositionObserverHandle
import androidx.compose.runtime.tooling.CompositionRegistrationObserver
import androidx.compose.runtime.tooling.ObservableComposition
import java.util.concurrent.atomic.AtomicLong

// Counts composing, in every composition the running recomposers hold,
// from when it is made until it is closed: passes over a composition,
// scopes visited, and scopes made to run their code again by a change of
// a plain state they read. A scope that reads a derived state is visited
// whenever what that state is worked out from changes, and left alone when
// its value did not; only a plain state's change always runs it again.
@OptIn(ExperimentalComposeRuntimeApi::class)
internal class Recompositions : AutoCloseable {
    class Counts(val passes: Long, val visited: Long, val rerun: Long)

    private val passes = AtomicLong()
    private val visited = AtomicLong()
    private val rerun = AtomicLong()
    private val handles = mutableListOf<CompositionObserverHandle>()

    private val counter = object : CompositionObserver {
        override fun onBeginComposition(composition: ObservableComposition) {
            passes.incrementAndGet()
        }

        override fun onScopeEnter(scope: RecomposeScope) {
            visited.incrementAndGet()
        }

        override fun onScopeInvalidated(scope: RecomposeScope, value: Any?) {
            if (value == null || !isDerived(value)) rerun.incrementAndGet()
        }

        override fun onReadInScope(scope: RecomposeScope, value: Any) = Unit
        override fun onScopeExit(scope: RecomposeScope) = Unit
        override fun onEndComposition(composition: ObservableComposition) = Unit
        override fun onScopeDisposed(scope: RecomposeScope) = Unit
    }

    init {
        Recomposer.runningRecomposers.value.forEach { info ->
            val handle = info.observe(
                object : CompositionRegistrationObserver {
                    override fun onCompositionRegistered(composition: ObservableComposition) {
                        val handle = composition.setObserver(counter)
                        synchronized(handles) { handles.add(handle) }
                    }

                    override fun onCompositionUnregistered(composition: ObservableComposition) = Unit
                },
            )
            if (handle != null) synchronized(handles) { handles.add(handle) }
        }
    }

    // A derived state, by its class: the runtime keeps the type to itself.
    private fun isDerived(value: Any): Boolean = value.javaClass.name == "androidx.compose.runtime.DerivedSnapshotState"

    // What was counted since the last call.
    fun take(): Counts = Counts(passes.getAndSet(0), visited.getAndSet(0), rerun.getAndSet(0))

    override fun close() {
        synchronized(handles) {
            handles.forEach { it.dispose() }
            handles.clear()
        }
    }
}
