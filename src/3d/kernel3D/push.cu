#include <cassert>
#include <cuda_runtime.h>

#include "scope/init/flags.hpp"
#include "scope/init/init.hpp"

#include "../args.hpp"

#define NAME "Comm_3d_kernel3D_push"

__global__ void Comm_3d_kernel3D_push_kernel(void *__restrict__ dst, const void *__restrict__ src,
                                             const cudaExtent allocExtent, const cudaExtent copyExtent,
                                             const size_t elemSize) {

  const unsigned int tz = blockDim.z * blockIdx.z + threadIdx.z;
  const unsigned int ty = blockDim.y * blockIdx.y + threadIdx.y;
  const unsigned int tx = blockDim.x * blockIdx.x + threadIdx.x;

  for (unsigned int zi = tz; zi < copyExtent.depth; zi += blockDim.z * gridDim.z) {
    for (unsigned int yi = ty; yi < copyExtent.height; yi += blockDim.y * gridDim.y) {
      for (unsigned int xi = tx; xi < copyExtent.width; xi += blockDim.x * gridDim.x) {
        unsigned int ii = zi * allocExtent.height * allocExtent.width + yi * allocExtent.width + xi;
        if (4 == elemSize) {
          uint32_t *pDst       = reinterpret_cast<uint32_t *>(dst);
          const uint32_t *pSrc = reinterpret_cast<const uint32_t *>(src);
          uint32_t v           = pSrc[ii];
          pDst[ii]             = v;
        } else if (8 == elemSize) {
          uint64_t *pDst       = reinterpret_cast<uint64_t *>(dst);
          const uint64_t *pSrc = reinterpret_cast<const uint64_t *>(src);
          pDst[ii]             = pSrc[ii];
        } else {
          char *pDst       = reinterpret_cast<char *>(dst);
          const char *pSrc = reinterpret_cast<const char *>(src);
          memcpy(&pDst[ii * elemSize], &pSrc[ii * elemSize], elemSize);
        }
      }
    }
  }
}

inline int64_t nextPowerOfTwo(int64_t x) {
  x--;
  x |= x >> 1;
  x |= x >> 2;
  x |= x >> 4;
  x |= x >> 8;
  x |= x >> 16;
  x |= x >> 32;
  x++;
  return x;
}

inline dim3 make_block_dim(const cudaExtent extent, int64_t threads) {
  assert(threads <= 1024);
  dim3 ret;
  ret.x = std::min(threads, nextPowerOfTwo(extent.width));
  threads /= ret.x;
  ret.y = std::min(threads, nextPowerOfTwo(extent.height));
  threads /= ret.y;
  ret.z = std::min(threads, nextPowerOfTwo(extent.depth));

  // if z is too big, push down into y
  if (ret.z > 64) {
    ret.y *= (ret.z / 64);
    ret.z = 64;
  }

  assert(ret.x <= 1024);
  assert(ret.y <= 1024);
  assert(ret.z <= 64); // maximum
  assert(ret.x * ret.y * ret.z <= 1024);
  return ret;
}

// to be used in benchmark loop
#define OR_SKIP_LOOP(stmt, msg)                                                                                        \
  if (PRINT_IF_ERROR(stmt)) {                                                                                          \
    state.SkipWithError(msg);                                                                                          \
    break;                                                                                                             \
  }

// during setup or teardown
#define OR_SKIP(stmt, msg)                                                                                             \
  if (PRINT_IF_ERROR(stmt)) {                                                                                          \
    state.SkipWithError(msg);                                                                                          \
  }

auto Comm_3d_kernel3D_push = [](benchmark::State &state, const int gpu0, const int gpu1) {
  if (!has_cuda) {
    state.SkipWithError(NAME " no CUDA device found");
  }

#if SCOPE_USE_NVTX == 1
  {
    std::stringstream name;
    name << NAME << "/" << gpu0 << "/" << gpu1 << "/" << state.range(0) << "/" << state.range(1) << "/"
         << state.range(2);
    nvtxRangePush(name.str().c_str());
  }
#endif

  OR_SKIP(utils::cuda_reset_device(gpu0), NAME " failed to reset CUDA device");
  OR_SKIP(utils::cuda_reset_device(gpu1), NAME " failed to reset CUDA device");

  // create stream on src gpu (push)
  OR_SKIP(cudaSetDevice(gpu0), NAME "failed to create stream");
  cudaStream_t stream = nullptr;
  OR_SKIP(cudaStreamCreate(&stream), NAME "failed to create stream");

  // Start and stop events on src gpu (push)
  cudaEvent_t start = nullptr;
  cudaEvent_t stop  = nullptr;
  OR_SKIP(cudaEventCreate(&start), NAME " failed to create event");
  OR_SKIP(cudaEventCreate(&stop), NAME " failed to create event");

  // target size to transfer
  cudaExtent copyExt;
  copyExt.width  = static_cast<size_t>(state.range(0));
  copyExt.height = static_cast<size_t>(state.range(1));
  copyExt.depth  = static_cast<size_t>(state.range(2));
  const size_t copyBytes = copyExt.width * copyExt.height * copyExt.depth;

  // properties of the allocation
  cudaExtent allocExt;
  allocExt.width  = 512; // how many bytes in a row
  allocExt.height = 512; // how many rows in a plane
  allocExt.depth  = 512;

  cudaPitchedPtr src, dst;

  // allocate on gpu0 and enable peer access
  OR_SKIP(cudaSetDevice(gpu0), NAME "failed to set device");
  OR_SKIP(cudaMalloc3D(&src, allocExt), NAME " failed to perform cudaMalloc3D");
  allocExt.width = src.pitch;
  OR_SKIP(cudaMemset3D(src, 0, allocExt), NAME " failed to perform src cudaMemset3D");
  if (gpu0 != gpu1) {
    cudaError_t err = cudaDeviceEnablePeerAccess(gpu1, 0);
    if (cudaSuccess != err && cudaErrorPeerAccessAlreadyEnabled != err) {
      state.SkipWithError(NAME " failed to ensure peer access");
    }
  }

  // allocate on gpu1 and enable peer access
  OR_SKIP(cudaSetDevice(gpu1), NAME "failed to set device");
  OR_SKIP(cudaMalloc3D(&dst, allocExt), NAME " failed to perform cudaMalloc3D");
  OR_SKIP(cudaMemset3D(dst, 0, allocExt), NAME " failed to perform src cudaMemset3D");
  if (gpu0 != gpu1) {
    cudaError_t err = cudaDeviceEnablePeerAccess(gpu0, 0);
    if (cudaSuccess != err && cudaErrorPeerAccessAlreadyEnabled != err) {
      state.SkipWithError(NAME " failed to ensure peer access");
    }
  }

  // 4 bytes per thread
  size_t elemSize = 4;
  // convert alloc and copy extent to be in terms of elemSize chunks
  assert(allocExt.width % elemSize == 0);
  allocExt.width /= elemSize;
  assert(copyExt.width % elemSize == 0);
  copyExt.width /= elemSize;

  dim3 blockDim = make_block_dim(copyExt, 512);
  dim3 gridDim;
  gridDim.x = (copyExt.width + blockDim.x - 1) / blockDim.x;
  gridDim.y = (copyExt.height + blockDim.y - 1) / blockDim.y;
  gridDim.z = (copyExt.depth + blockDim.z - 1) / blockDim.z;

  // push, so run kernel on source device
  OR_SKIP(cudaSetDevice(gpu0), NAME " unable to set push device");

  for (auto _ : state) {
    // Start copy
    OR_SKIP_LOOP(cudaEventRecord(start, stream), NAME " failed to record start event");

    Comm_3d_kernel3D_push_kernel<<<gridDim, blockDim, 0, stream>>>(dst.ptr, src.ptr, allocExt, copyExt, elemSize);
    OR_SKIP_LOOP(cudaGetLastError(), "kernel");

    OR_SKIP_LOOP(cudaEventRecord(stop, stream), NAME " failed to record stop event");

    // Wait for all copies to finish
    OR_SKIP_LOOP(cudaEventSynchronize(stop), NAME " failed to synchronize");

    // Get the transfer time
    float millis;
    OR_SKIP_LOOP(cudaEventElapsedTime(&millis, start, stop), NAME " failed to compute elapsed tiume");
    state.SetIterationTime(millis / 1000);
  }

  state.SetBytesProcessed(int64_t(state.iterations()) * int64_t(copyBytes));
  state.counters["bytes"] = copyBytes;
  state.counters["gpu0"]  = gpu0;
  state.counters["gpu1"]  = gpu1;
  state.counters["dbx"]  = blockDim.x;
  state.counters["dby"]  = blockDim.y;
  state.counters["dbz"]  = blockDim.z;
  state.counters["dgx"]  = gridDim.x;
  state.counters["dgy"]  = gridDim.y;
  state.counters["dgz"]  = gridDim.x;

  OR_SKIP(cudaEventDestroy(start), "cudaEventDestroy");
  OR_SKIP(cudaEventDestroy(stop), "cudaEventDestroy");
  OR_SKIP(cudaStreamDestroy(stream), "cudaStreamDestroy");
  OR_SKIP(cudaFree(src.ptr), "cudaFree");
  OR_SKIP(cudaFree(dst.ptr), "cudaFree");

#if SCOPE_USE_NVTX == 1
  nvtxRangePop();
#endif
};

static void registerer() {
  std::string name;
  for (size_t i = 0; i < unique_cuda_device_ids().size(); ++i) {
    for (size_t j = i; j < unique_cuda_device_ids().size(); ++j) {
      auto gpu0 = unique_cuda_device_ids()[i];
      auto gpu1 = unique_cuda_device_ids()[j];
      int ok1, ok2;
      if (!PRINT_IF_ERROR(cudaDeviceCanAccessPeer(&ok1, gpu0, gpu1)) &&
          !PRINT_IF_ERROR(cudaDeviceCanAccessPeer(&ok2, gpu1, gpu0))) {
        if ((ok1 && ok2) || i == j) {
          name = std::string(NAME) + "/" + std::to_string(gpu0) + "/" + std::to_string(gpu1);
          benchmark::RegisterBenchmark(name.c_str(), Comm_3d_kernel3D_push, gpu0, gpu1)->TINY_ARGS()->UseManualTime();
        }
      }
    }
  }
}

SCOPE_REGISTER_AFTER_INIT(registerer, NAME);
