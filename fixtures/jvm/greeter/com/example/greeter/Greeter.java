package com.example.greeter;

import java.util.List;

/** Greets people, with a couple of Java shapes the driver has to map. */
public class Greeter {
  /** Default separator between the prefix and the name. */
  public static final String DEFAULT_PREFIX = "Hello";

  /** Number of greetings this instance has produced. */
  public int count;

  private final String prefix;

  public Greeter() {
    this(DEFAULT_PREFIX);
  }

  public Greeter(String prefix) {
    this.prefix = prefix;
  }

  /** Greets {@code name}.
   * @param name The person to greet.
   */
  public String greet(String name) {
    count++;
    return prefix + ", " + name + "!";
  }

  /** Greets everyone in the list. */
  public List<String> greetAll(List<String> names) {
    java.util.ArrayList<String> out = new java.util.ArrayList<>();
    for (String name : names) {
      out.add(greet(name));
    }
    return out;
  }

  /** Greets {@code name} and hands the result to {@code listener}. */
  public void greetAsync(String name, Listener listener) {
    listener.onGreeting(greet(name));
  }

  /** The library version. */
  public static int version() {
    return 3;
  }

  /** How loudly to greet. */
  public enum Volume {
    QUIET,
    NORMAL,
    LOUD,
  }

  /** Receives a greeting. */
  public interface Listener {
    void onGreeting(String greeting);
  }
}
