# Contract: `@` menu options

New infixes in the `magit-review` transient. The existing suffixes are
unchanged.

```text
Options
 -t Separate thread        (--thread)
 -n New thread each time   (--new-thread)   only matters with --thread
Comment       Review              Walkthrough
 c ...         s ...               w ...
 d ...         p ...               W ...
               l ...
               k ...
```

| Behaviour            | Rule                                                          |
|----------------------|---------------------------------------------------------------|
| Default              | Both off: hand-offs go to the main instance, as today.        |
| Session persistence  | The value is kept on exit and quit (`:remember-value`).       |
| Saved default        | `C-x C-s` in the menu, standard transient save.               |
| Read by              | `magit-review-send`, `magit-review-paste`,                    |
|                      | `magit-review-comment-send`, all through `(transient-args     |
|                      | 'magit-review)`, so it also works outside the menu.           |
| Not read by          | `@ c`, `@ l`, `@ k`, `@ w`, `@ W`.                            |
