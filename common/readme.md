# Common code

Stores code which can be used amongst all the components of the operating system, such as OS, kernel, shell, and the foundational libraries. There are a couple of constraints placed upon code put here:

* **Self-Contained**: Modules must not depend on anything else but itself and other `common` modules. For other dependencies, opt for dependency injection through a well-defined interface. 

## Examples
### An implementation for a file system
The business logic can be stored in a `common` module, which interacts with the underlying storage device through an `IO` interface, providing access. The implementation then serves the file system requests through the `FS` interface.
