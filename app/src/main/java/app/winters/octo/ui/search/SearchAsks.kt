package app.winters.octo.ui.search

import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject
import javax.inject.Singleton

// Searches asked for from elsewhere in the app (the live player's "Find
// this song in Octo"): the app goes to Search, and Search takes the words.
@Singleton
class SearchAsks @Inject constructor() {
    private val _query = MutableStateFlow<String?>(null)

    // The words to search for, until Search takes them.
    val query: StateFlow<String?> = _query

    // Goes up with each ask, so the app goes to Search every time.
    private val _asked = MutableStateFlow(0)
    val asked: StateFlow<Int> = _asked

    fun ask(words: String) {
        if (words.isBlank()) return
        _query.value = words.trim()
        _asked.value++
    }

    // Search took the words.
    fun took(words: String) {
        _query.compareAndSet(words, null)
    }
}

// For the app's shell, which has no view model of its own for this.
@HiltViewModel
class SearchShellViewModel @Inject constructor(val asks: SearchAsks) : ViewModel()
