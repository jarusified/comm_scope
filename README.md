# Comm|Scope

CUDA- and NUMA-Aware Multi-CPU / Multi-GPU communication benchmarks for [C3SR Scope](https://github.com/c3sr/scope).

Docker images are [available](https://hub.docker.com/r/c3sr/comm_scope/) on Docker Hub.

## Contributors

* [Carl Pearson](mailto:pearson@illinois.edu)
* [Sarah Hashash](mailto:hashash2@illinois.edu)

## Prerequisites

* g++ >= 4.9
* CUDA toolkit >= 8.0

## Documentation

See the `docs` folder for a description of the benchmarks.

## Bumping the Version

Update the changelog.

Install bump2version

```pip install --user bump2version```

Check that everything seems good (minor version, for example)

```bump2version --dry-run minor --verbose```

Actually bump the version

```bump2version minor```

Push the changes

```git push && git push --tags```

## Adding or changing names of source files

Comm|Scope uses sugar to inform CMake about source files

From within the scope directory tree

```
cd scopes
python ../tools/generate_sugar_files.py --top comm_scope
```

# Changelog

## v0.7.1 (April 5 2019)

* Add v0.7.0 and v0.7.1 changelog

## v0.7.0 (April 5 2019)

* Make POWER's cache flushing code match the linux kernel.
* rename "Coherence" benchmarks to "Demand"
* remove cudaSTreamSynchronize from the timing path of zerocopy-duplex, demand-duplex, and prefetch-duplex
* Transition to better use of CMake's CUDA language support
* Use NVCC's compiler defines to check the CUDA version
* Disable Comm|Scope by default during Scope compilation

## v0.6.3 (Dec 20 2018)

* Add `USE_NUMA` CMake option
* Fix compile errors when USE_NUMA=0 or NUMA cannot be found 

## v0.6.2

* Fix checking non-existent cudaDeviceProp field in CUDA < 9

## v0.6.1

* Conform to updated SCOPE_REGSITER_AFTER_INIT

## v0.6.0

* Add unified memory allocation benchmarks
* Flush CPU caches in zero-copy benchmarks
* Add zerocopy duplex benchmarks
* Add unified memory prefetch duplex benchmark
* Add unified memory demand duplex benchmark
* Conform to updated SCOPE_REGSITER_AFTER_INIT

## v0.5.0

* Add zero-copy benchmarks
* Don't use nvToolsExt

## v0.4.0

* Add multithreaded Coherence GPU to Host benchmark
* Programatically register most benchmarks based on system configuration
* use cudaMemcpyAsync in numa-memcpy
* Add travis and Dockerfiles
* Use `aligned_alloc` in numa-memcpy/pinned-to-gpu
* Add x86 and POWER cache control functions

## v0.3.0

* Rework documentation
* Use `target_include_scope_directories` and `target_link_scope_libraries`.
* Use Clara for flags.
* Remove numa/rd and numa/wr.

## v0.2.0

* Add `--numa_ids` command line flag.
* Use `--cuda_device_ids` and --`numa_ids` to select CUDA and NUMA devices for benchmarks.

