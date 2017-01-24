#include <dlib/dnn/cuda_utils>

// ---------------------------------------------------------------------------

__global__ void idla::impl::applying_forward_differencing(
    const float* input_tensor,
    float* output_tensor,
    long in_nk,
    long in_nr,
    long in_nc,
    long nbhd_nr,
    long nbhd_nc,
    long n
)
{
    for (auto i : dlib::grid_stride_range(0, n))
    {
        // Find neighborhood indices
        long nbhd_c = i/nbhd_nc % in_nc;               // also center column
        long nbhd_r = i/nbhd_nc/in_nc/nbhd_nr % in_nr; // also center row
        long k = i/nbhd_nc/in_nc/nbhd_nr/in_nr % in_nk;
        long sample = i/nbhd_nc/in_nc/nbhd_nr/in_nr/in_nk;

        // Find in-neighborhood indices
        long in_nbhd_c = i % nbhd_nc;
        long in_nbhd_r = i/nbhd_nc/in_nc % nbhd_nr;

        // Find the second input tensor indices
        long in_c = nbhd_c - nbhd_nc/2 + in_nbhd_c;
        long in_r = nbhd_r - nbhd_nr/2 + in_nbhd_r;

        if (in_c <= 0 || in_r <= 0 || in_nc <= in_c ||  in_nr <= in_r) {
            output_tensor[i] = 0.0;
        }
        else {
            long idx1 = ((2*sample*in_nk + k)*in_nr + nbhd_r)*in_nc + nbhd_c;
            long idx2 = (((2*sample+1)*in_nk + k)*in_nr + in_r)*in_nc + in_c;
            output_tensor[i] = input_tensor[idx1]-input_tensor[idx2];
        }
    }
}

// ---------------------------------------------------------------------------

__global__ void idla::impl::applying_reverse_differencing(
    const float* input_tensor,
    float* output_tensor,
    long in_nk,
    long in_nr,
    long in_nc,
    long nbhd_nr,
    long nbhd_nc,
    long n
)
{
    for (auto i : dlib::grid_stride_range(0, n))
    {
        long nbhd_c = i/nbhd_nc % in_nc;
        long nbhd_r = i/nbhd_nc/in_nc/nbhd_nr % in_nr;
        long k = i/nbhd_nc/in_nc/nbhd_nr/in_nr % in_nk;
        long sample = i/nbhd_nc/in_nc/nbhd_nr/in_nr/in_nk;

        long in_nbhd_c = i % nbhd_nc;
        long in_nbhd_r = i/nbhd_nc/in_nc % nbhd_nr;

        long in_c = nbhd_c - nbhd_nc/2 + in_nbhd_c;
        long in_r = nbhd_r - nbhd_nr/2 + in_nbhd_r;

        if (in_c <= 0 || in_r <= 0 || in_nc <= in_c ||  in_nr <= in_r) {
            output_tensor[i] = 0.0;
        }
        else {
            long idx1 = (((2*sample+1)*in_nk + k)*in_nr + nbhd_r)*in_nc + nbhd_c;
            long idx2 = ((2*sample*in_nk + k)*in_nr + in_r)*in_nc + in_c;
            output_tensor[i] = input_tensor[idx1]-input_tensor[idx2];
        }
    }
}

// ---------------------------------------------------------------------------

__global__ void idla::impl::get_gradient(
    const float* gradient_input,
    float* gradient_output,
    long num_samples,
    long out_nk,
    long out_nr,
    long out_nc,
    long nbhd_nr,
    long nbhd_nc,
    long n
)
{
    for (auto i : dlib::grid_stride_range(0, n))
    {
        long out_c = i % out_nc;
        long out_r = i/out_nc % out_nr;
        long k = i/out_nc/out_nr % out_nk;
        long sample = i/out_nc/out_nr/out_nk;

        gradient_output[i] = 0;

        long flag = (sample % 2 == 0);
        for (long r = out_r*nbhd_nr; r < (out_r+1)*nbhd_nr; ++r) {
            long offset = (((1-flag)*num_samples + sample)*out_nk + k*out_nr*nbhd_nr + r)*out_nc*nbhd_nc;
            for (long c = out_c*nbhd_nc; c < (out_c+1)*nbhd_nc; ++c) {
                gradient_output[i] += gradient_input[ + offset + c];
            }
        }

        // Specify in-neighborhood indexes
        long out_nbhd_r = 0;
        long out_nbhd_c = 0;

        long r_off = nbhd_nr/2;
        for (long r = out_r+r_off; r > out_r-r_off; --r) {
            if (r < 0 || r >= out_nr) {
                ++out_nbhd_r;
                continue;
            }

            long offset = (((flag*num_samples + sample)*out_nk + k)*out_nr*nbhd_nr + r*nbhd_nr + out_nbhd_r)*out_nc*nbhd_nc;
            long c_off = nbhd_nc/2;
            ++out_nbhd_r;

            for (long c = out_c+c_off; c > out_c-c_off; --c) {
                if (c < 0 || c >= out_nc) {
                    ++out_nbhd_c;
                    continue;
                }

                gradient_output[i] += -gradient_input[offset + c*nbhd_nc + out_nbhd_c];
                ++out_nbhd_c;
            }
        }
    }
}

// ---------------------------------------------------------------------------
