// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Lib {
    /// @notice Compare two number within a 3 percent difference
    /// @dev    The relative difference is measured in terms of the smallest number
    /// @param  a_      first mumber
    /// @param  b_      second number
    /// @return result_ whether they are similar or not
    function similar(uint256 a_, uint256 b_) public pure returns (bool result_) {
        if (a_ == 0 || b_ == 0) revert("LIB:Can't compare to 0");
        uint256 maxPercentDif_ = 3;
        uint256 dif_;
        uint256 smallest_;
        if (a_ >= b_) {
            dif_ = a_ - b_;
            smallest_ = b_;
        } else {
            dif_ = b_ - a_;
            smallest_ = a_;
        }
        dif_ *= 100;
        if (dif_ / smallest_ < maxPercentDif_) result_ = true;
    }

    /// @notice Get a random number in a specified range
    /// @param  min_    minimum value
    /// @param  max_    maximum value
    /// @param  seed_   seed to generate random number
    /// @return number_ random number in specified range
    function getRandomNumberInRange(uint256 min_, uint256 max_, uint256 seed_) public pure returns (uint256 number_) {
        number_ = (seed_ % (max_ - min_)) + min_;
    }

    /// @notice Check an array for repeated entries
    /// @param  array_ array of uint256
    /// @return valid_ whether there are repeated entries or not
    function repeatedEntries(uint16[] calldata array_) public pure returns (bool valid_) {
        uint256 size_ = array_.length;
        for (uint256 i_ = 0; i_ < size_; i_++) {
            for (uint256 j_ = 0; j_ < size_; j_++) {
                if (i_ != j_) {
                    if (array_[i_] == array_[j_]) valid_ = true;
                }
            }
        }
    }

    /// @notice Check an array for repeated entries
    /// @param  array_ array of addresses
    /// @return valid_ whether there are repeated entries or not
    function repeatedEntries(address[] calldata array_) public pure returns (bool valid_) {
        uint256 size_ = array_.length;
        for (uint256 i_ = 0; i_ < size_; i_++) {
            for (uint256 j_ = 0; j_ < size_; j_++) {
                if (i_ != j_) {
                    if (array_[i_] == array_[j_]) valid_ = true;
                }
            }
        }
    }

    /// @notice Get the sum of all ements in array
    /// @param  array_ array
    /// @return sum_ sum of all elements in array
    function sumOfElements(uint256[] calldata array_) public pure returns (uint256 sum_) {
        uint256 size_ = array_.length;
        for (uint256 i_ = 0; i_ < size_; i_++) {
            sum_ += array_[i_];
        }
    }

    /// @notice Add two vectors
    /// @param  a_ first array
    /// @param  b_ second array
    /// @return sum_ sum of both vectors
    function vectorSum(uint256[] calldata a_, uint256[] calldata b_) public pure returns (uint256[] memory sum_) {
        assert(a_.length == b_.length);
        uint256 size_ = a_.length;
        sum_ = new uint256[](size_);
        for (uint256 i_ = 0; i_ < size_; i_++) {
            sum_[i_] = a_[i_] + b_[i_];
        }
    }

    /// @notice Compares all the elements of two vectors
    /// @param  a_ first array
    /// @param  b_ second array
    /// @return equal_ whether or not both vectors are the same
    function vectorEquals(uint256[] calldata a_, uint256[] calldata b_) public pure returns (bool equal_) {
        assert(a_.length == b_.length);
        uint256 size_ = a_.length;
        equal_ = true;
        for (uint256 i_ = 0; i_ < size_; i_++) {
            if (a_[i_] != b_[i_]) equal_ = false;
        }
    }
}
