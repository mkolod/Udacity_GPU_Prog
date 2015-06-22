// Homework 2
// Image Blurring
//
// In this homework we are blurring an image. To do this, imagine that we have
// a square array of weight values. For each pixel in the image, imagine that we
// overlay this square array of weights on top of the image such that the center
// of the weight array is aligned with the current pixel. To compute a blurred
// pixel value, we multiply each pair of numbers that line up. In other words, we
// multiply each weight with the pixel underneath it. Finally, we add up all of the
// multiplied numbers and assign that value to our output for the current pixel.
// We repeat this process for all the pixels in the image.

// To help get you started, we have included some useful notes here.

//****************************************************************************

// For a color image that has multiple channels, we suggest separating
// the different color channels so that each color is stored contiguously
// instead of being interleaved. This will simplify your code.

// That is instead of RGBARGBARGBARGBA... we suggest transforming to three
// arrays (as in the previous homework we ignore the alpha channel again):
//  1) RRRRRRRR...
//  2) GGGGGGGG...
//  3) BBBBBBBB...
//
// The original layout is known an Array of Structures (AoS) whereas the
// format we are converting to is known as a Structure of Arrays (SoA).

// As a warm-up, we will ask you to write the kernel that performs this
// separation. You should then write the "meat" of the assignment,
// which is the kernel that performs the actual blur. We provide code that
// re-combines your blurred results for each color channel.

//****************************************************************************

// You must fill in the gaussian_blur kernel to perform the blurring of the
// inputChannel, using the array of weights, and put the result in the outputChannel.

// Here is an example of computing a blur, using a weighted average, for a single
// pixel in a small image.
//
// Array of weights:
//
//  0.0  0.2  0.0
//  0.2  0.2  0.2
//  0.0  0.2  0.0
//
// Image (note that we align the array of weights to the center of the box):
//
//    1  2  5  2  0  3
//       -------
//    3 |2  5  1| 6  0       0.0*2 + 0.2*5 + 0.0*1 +
//      |       |
//    4 |3  6  2| 1  4   ->  0.2*3 + 0.2*6 + 0.2*2 +   ->  3.2
//      |       |
//    0 |4  0  3| 4  2       0.0*4 + 0.2*0 + 0.0*3
//       -------
//    9  6  5  0  3  9
//
//         (1)                         (2)                 (3)
//
// A good starting place is to map each thread to a pixel as you have before.
// Then every thread can perform steps 2 and 3 in the diagram above
// completely independently of one another.

// Note that the array of weights is square, so its height is the same as its width.
// We refer to the array of weights as a filter, and we refer to its width with the
// variable filterWidth.

//****************************************************************************

// Your homework submission will be evaluated based on correctness and speed.
// We test each pixel against a reference solution. If any pixel differs by
// more than some small threshold value, the system will tell you that your
// solution is incorrect, and it will let you try again.

// Once you have gotten that working correctly, then you can think about using
// shared memory and having the threads cooperate to achieve better performance.

//****************************************************************************

// Also note that we've supplied a helpful debugging function called checkCudaErrors.
// You should wrap your allocation and copying statements like we've done in the
// code we're supplying you. Here is an example of the unsafe way to allocate
// memory on the GPU:
//
// cudaMalloc(&d_red, sizeof(unsigned char) * numRows * numCols);
//
// Here is an example of the safe way to do the same thing:
//
// checkCudaErrors(cudaMalloc(&d_red, sizeof(unsigned char) * numRows * numCols));
//
// Writing code the safe way requires slightly more typing, but is very helpful for
// catching mistakes. If you write code the unsafe way and you make a mistake, then
// any subsequent kernels won't compute anything, and it will be hard to figure out
// why. Writing code the safe way will inform you as soon as you make a mistake.

// Finally, remember to free the memory you allocate at the end of the function.

//****************************************************************************

#include "utils.h"

// GLOBAL VARS ON DEVICE!
unsigned char *d_red, *d_green, *d_blue;
float         *d_filter;

// devicel functions:
__device__ int min_int(int a, int b){
  if (a <= b) return a;
  else return b;
}
__device__ int max_int(int a, int b) {
  if (a>=b) return a;
  else return b;
}

__global__
void gaussian_blur(const unsigned char* const inputChannel,
                   unsigned char* const outputChannel,
                   int numRows, int numCols,
                   const float* const filter, const int filterWidth)
{
  // TODO

  // NOTE: Be sure to compute any intermediate results in floating point
  // before storing the final result as unsigned char.

  // NOTE: If a thread's absolute position 2D position is within the image, but some of
  // its neighbors are outside the image, then you will need to be extra careful. Instead
  // of trying to read such a neighbor value from GPU memory (which won't work because
  // the value is out of bounds), you should explicitly clamp the neighbor values you read
  // to be within the bounds of the image. If this is not clear to you, then please refer
  // to sequential reference solution for the exact clamping semantics you should follow.

  const int2 thread_2D_pos = make_int2(blockIdx.x*blockDim.x + threadIdx.x,
                                        blockIdx.y*blockDim.y + threadIdx.y);
  // ensure we don't access memory outside of bounds!
  if(thread_2D_pos.x >= numCols || thread_2D_pos.y >= numRows) return;
  const int thread_1D_pos = thread_2D_pos.y*numCols + thread_2D_pos.x;


  float result = 0.f;
  //For every value in the filter around the pixel (c, r)
  for (int filter_r = -filterWidth/2; filter_r <= filterWidth/2; ++filter_r) {
    for (int filter_c = -filterWidth/2; filter_c <= filterWidth/2; ++filter_c) {
      //Find the global image position for this filter position
      //clamp to boundary of the image
      int image_r = min_int(max_int(thread_2D_pos.y + filter_r, 0), static_cast<int>(numRows - 1));
      int image_c = min_int(max_int(thread_2D_pos.x + filter_c, 0), static_cast<int>(numCols - 1));

      if (thread_1D_pos == 0) {
        printf("filter_r: %d, filter_c: %d, image_r: %d, image_c: %d \n",filter_r,filter_c,image_r,image_c);
      }

      float image_value = static_cast<float>(inputChannel[image_r * numCols + image_c]);
      float filter_value = filter[(filter_r + filterWidth/2) * filterWidth + filter_c + filterWidth/2];

      result += image_value * filter_value;
    }
  }

  outputChannel[thread_1D_pos] = result;

}

//This kernel takes in an image represented as a uchar4 and splits
//it into three images consisting of only one color channel each
__global__
void separateChannels(const uchar4* const inputImageRGBA,
                      int numRows,
                      int numCols,
                      unsigned char* const redChannel,
                      unsigned char* const greenChannel,
                      unsigned char* const blueChannel)
{


  const int2 thread_2D_pos = make_int2(blockIdx.x*blockDim.x + threadIdx.x,
                                       blockIdx.y*blockDim.y + threadIdx.y);
  // ensure we don't access memory outside of bounds!
  if(thread_2D_pos.x >= numCols || thread_2D_pos.y >= numRows) return;

  const int thread_1D_pos = thread_2D_pos.y*numCols + thread_2D_pos.x;

  redChannel[thread_1D_pos] = inputImageRGBA[thread_1D_pos].x;
  greenChannel[thread_1D_pos] = inputImageRGBA[thread_1D_pos].y;
  blueChannel[thread_1D_pos] = inputImageRGBA[thread_1D_pos].z;

}

//This kernel takes in three color channels and recombines them
//into one image.  The alpha channel is set to 255 to represent
//that this image has no transparency.
__global__
void recombineChannels(const unsigned char* const redChannel,
                       const unsigned char* const greenChannel,
                       const unsigned char* const blueChannel,
                       uchar4* const outputImageRGBA,
                       int numRows,
                       int numCols)
{
  const int2 thread_2D_pos = make_int2( blockIdx.x * blockDim.x + threadIdx.x,
                                        blockIdx.y * blockDim.y + threadIdx.y);

  const int thread_1D_pos = thread_2D_pos.y * numCols + thread_2D_pos.x;

  //make sure we don't try and access memory outside the image
  //by having any threads mapped there return early
  if (thread_2D_pos.x >= numCols || thread_2D_pos.y >= numRows)
    return;

  unsigned char red   = redChannel[thread_1D_pos];
  unsigned char green = greenChannel[thread_1D_pos];
  unsigned char blue  = blueChannel[thread_1D_pos];

  //Alpha should be 255 for no transparency
  uchar4 outputPixel = make_uchar4(red, green, blue, 255);

  outputImageRGBA[thread_1D_pos] = outputPixel;
}


void allocateMemoryAndCopyToGPU(const size_t numRowsImage, const size_t numColsImage,
                                const float* const h_filter, const size_t filterWidth)
{

  //allocate memory for the three different channels
  //original
  checkCudaErrors(cudaMalloc(&d_red,   sizeof(unsigned char) * numRowsImage * numColsImage));
  checkCudaErrors(cudaMalloc(&d_green, sizeof(unsigned char) * numRowsImage * numColsImage));
  checkCudaErrors(cudaMalloc(&d_blue,  sizeof(unsigned char) * numRowsImage * numColsImage));

  // Now allocate memory for filter and copy from host to device ptr.
  checkCudaErrors(cudaMalloc((void**)&d_filter,sizeof(float)*filterWidth*filterWidth));
  checkCudaErrors(cudaMemcpy(d_filter,h_filter,sizeof(float)*filterWidth*filterWidth,
                             cudaMemcpyHostToDevice));

  // Testing - inspect h_filter:
  //for(int i=0; i<filterWidth; i++) {
  //  for(int j=0; j<filterWidth; j++) {
  //    printf("i: %d, j: %d, val: %f \n",i,j,*(h_filter +i*filterWidth + j));
  //  }
  //}

}

void your_gaussian_blur(const uchar4 * const h_inputImageRGBA, uchar4 * const d_inputImageRGBA,
                        uchar4* const d_outputImageRGBA, const size_t numRows, const size_t numCols,
                        unsigned char *d_redBlurred,
                        unsigned char *d_greenBlurred,
                        unsigned char *d_blueBlurred,
                        const int filterWidth)
{

  // printf("numRows: %lu, numCols: %lu\n",numRows,numCols);

  //TODO: Set reasonable block size (i.e., number of threads per block)
  const dim3 blockSize(20,20,1);  // 20*20 = 400 threads per block

  //TODO:
  //Compute correct grid size (i.e., number of blocks per kernel launch)
  //from the image size and and block size.
  const dim3 gridSize(numCols/blockSize.x+1,numRows/blockSize.y+1,1);

  //printf("block size x: %d, y: %d \n",blockSize.x,blockSize.y);
  //printf("grid size x: %d, y: %d \n",gridSize.x,gridSize.y);

  //TODO: Launch a kernel for separating the RGBA image into different color channels
  separateChannels<<<gridSize,blockSize>>>(d_inputImageRGBA,numRows,numCols,
                                           d_red,d_green,d_blue);
  cudaDeviceSynchronize(); checkCudaErrors(cudaGetLastError());

  //TODO: Call your convolution kernel here 3 times, once for each color channel.
  gaussian_blur<<<gridSize,blockSize>>>(d_red,d_redBlurred,numRows,numCols,
                                        d_filter,filterWidth);
  cudaDeviceSynchronize(); checkCudaErrors(cudaGetLastError());
  gaussian_blur<<<gridSize,blockSize>>>(d_green,d_greenBlurred,numRows,numCols,
                                        d_filter,filterWidth);
  cudaDeviceSynchronize(); checkCudaErrors(cudaGetLastError());
  gaussian_blur<<<gridSize,blockSize>>>(d_blue,d_blueBlurred,numRows,numCols,
                                        d_filter,filterWidth);
  cudaDeviceSynchronize(); checkCudaErrors(cudaGetLastError());

  // Now we recombine your results. We take care of launching this kernel for you.
  //
  // NOTE: This kernel launch depends on the gridSize and blockSize variables,
  // which you must set yourself.
  recombineChannels<<<gridSize, blockSize>>>(d_redBlurred,
                                             d_greenBlurred,
                                             d_blueBlurred,
                                             d_outputImageRGBA,
                                             numRows,
                                             numCols);
  cudaDeviceSynchronize(); checkCudaErrors(cudaGetLastError());

}


//Free all the memory that we allocated
//TODO: make sure you free any arrays that you allocated
void cleanup() {
  checkCudaErrors(cudaFree(d_red));
  checkCudaErrors(cudaFree(d_green));
  checkCudaErrors(cudaFree(d_blue));
  checkCudaErrors(cudaFree(d_filter));
}