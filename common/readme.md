# Common code

Stores code which can be used amongst all the components of the operating system, such as OS, kernel, shell, and the foundational libraries. There are a couple of constraints placed upon code put here:

* **Self-Contained**: Modules must not depend on anything else but itself and other `common` modules. For other dependencies, opt for dependency injection through a well-defined interface. 

* **Modular**: The `common` code should be modularized, and adapted to the Zig build system. This allows us to better define boundaries between parts and architect the OS better. And also, the same code becomes reusable in many more places.

* **Testable**: By the virtue of modularization and dependency injection, the testing can be done on the development machine directly.

## Examples
### An implementation for a file system
The business logic can be stored in a `common` module, which interacts with the underlying storage device through an `IO` interface, providing access. The implementation then serves the file system requests through the `FS` interface.

Due to the modularity of this file system implementation, exact same code can serve both the file system layer in the kernel *and* user-space applications which deal with raw file system image files, for example. This same code can even be adapted to be used in applications outside Ceres. 

In short, this enables us to do One-VFS-to-Rule-Them-All.