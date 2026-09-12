package com.example.ktgreeter

import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Greets people, in the Kotlin shapes jnigen cannot carry across on its own.
 *
 * Each member here exists to pin one of them down:
 *  - [greet] has a default argument, which Kotlin compiles to a synthetic
 *    `greet$default` taking a bitmask, so Dart only ever sees full arity;
 *  - [greetAll] returns a `Flow`, which is an opaque object to JNI;
 *  - [tryGreet] returns a sealed class, whose subclass is invisible to Dart;
 *  - [greetSlowly] is `suspend`, the one shape jnigen already lowers itself
 *    (to a `Future`), so the bridge must leave it alone;
 *  - [shout] is overloaded, so jnigen numbers the second one `shout$1`;
 *  - [nickname] is nullable only because Kotlin says so: in the bytecode
 *    every reference is nullable;
 *  - [greetTo] takes a Kotlin `fun interface`, implemented from Dart;
 *  - [DEFAULT_PREFIX] and [version] live on the companion object.
 */
class KtGreeter(private val prefix: String = "Hello") {

  /** Greets [name], at [volume]. */
  fun greet(name: String, volume: Volume = Volume.NORMAL): String =
    "$prefix, $name${if (volume == Volume.LOUD) "!!!" else "!"}"

  /** One greeting per name, emitted as a cold flow. */
  fun greetAll(names: List<String>): Flow<String> = flow {
    for (name in names) emit(greet(name))
  }

  /** Greets [name] after suspending, so it resumes on another thread. */
  suspend fun greetSlowly(name: String): String {
    delay(1)
    return greet(name)
  }

  /** Greets [name], or says why it could not. */
  fun tryGreet(name: String): Reply =
    if (name.isEmpty()) Reply.Failed("empty name") else Reply.Ok(greet(name))

  /** Greets [name] loudly. */
  fun shout(name: String): String = greet(name, Volume.LOUD)

  /** Greets [name] loudly, [times] times over. */
  fun shout(name: String, times: Int): String =
    List(times) { shout(name) }.joinToString(" ")

  /** The first three letters of [name], or `null` when it is shorter. */
  fun nickname(name: String): String? = if (name.length > 3) name.take(3) else null

  /** Greets [name] and hands the greeting to [listener]. */
  fun greetTo(name: String, listener: Listener) = listener.onGreeting(greet(name))

  companion object {
    /** The prefix a greeter uses when none is given. */
    const val DEFAULT_PREFIX = "Hello"

    /** The library version. */
    fun version(): Int = 3
  }
}

/** Receives a greeting. */
fun interface Listener {
  fun onGreeting(greeting: String)
}

/** How loudly to greet. */
enum class Volume { QUIET, NORMAL, LOUD }

/** The outcome of [KtGreeter.tryGreet]. */
sealed class Reply {
  /** The greeting. */
  data class Ok(val text: String) : Reply()

  /** Why there is no greeting. */
  data class Failed(val reason: String) : Reply()
}
