package app.winters.octo.desktop.perf

import androidx.compose.runtime.ExperimentalComposeRuntimeApi
import androidx.compose.runtime.RecomposeScope
import androidx.compose.runtime.Recomposer
import androidx.compose.runtime.tooling.CompositionObserver
import androidx.compose.runtime.tooling.CompositionObserverHandle
import androidx.compose.runtime.tooling.CompositionRegistrationObserver
import androidx.compose.runtime.tooling.ObservableComposition
import java.util.concurrent.atomic.AtomicLong

// Counts how often composable scopes run again, in every composition the
// running recomposers hold, from when it is made until it is closed.
@OptIn(ExperimentalComposeRuntimeApi::class)
internal class Recompositions : AutoCloseable {
    private val scopes = AtomicLong()
    private val passes = AtomicLong()
    private val handles = mutableListOf<CompositionObserverHandle>()

    private val counter = object : CompositionObserver {
        override fun onBeginComposition(composition: ObservableComposition) {
            passes.incrementAndGet()
        }

        override fun onScopeEnter(scope: RecomposeScope) {
            scopes.incrementAndGet()
        }

        override fun onReadInScope(scope: RecomposeScope, value: Any) = Unit
        override fun onScopeExit(scope: RecomposeScope) = Unit
        override fun onEndComposition(composition: ObservableComposition) = Unit
        override fun onScopeInvalidated(scope: RecomposeScope, value: Any?) = Unit
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

    // Scopes run again, and composition passes, since the last call.
    fun take(): Pair<Long, Long> = scopes.getAndSet(0) to passes.getAndSet(0)

    override fun close() {
        synchronized(handles) {
            handles.forEach { it.dispose() }
            handles.clear()
        }
    }
}
