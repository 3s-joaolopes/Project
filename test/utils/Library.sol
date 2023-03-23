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
    /// @param  array_ array to check
    /// @return valid_ whether there are repeated entries or not
    function repeatedEntries(uint16[] calldata array_) public pure returns (bool valid_) {
        uint256 size = array_.length;
        for (uint256 i = 0; i < size; i++) {
            for (uint256 j = 0; j < size; j++) {
                if (i != j) {
                    if (array_[i] == array_[j]) valid_ = true;
                }
            }
        }
    }
}
