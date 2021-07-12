#import "MPR.h"
#import <libfive/tree/tree.hpp>
#import "mpr/tape.hpp"

@implementation MPR

+ (void)fillBuffer:(void *)buffer
{
    auto X = libfive::Tree::X();
    auto Y = libfive::Tree::Y();
    auto a = sqrt((X - 1)*(X - 1) + Y*Y) - 0.5;
    auto b = sqrt((X + 1)*(X + 1) + (Y + 1)*(Y + 1)) - 1.8;
    auto t = min(a, b);
    auto tape = mpr::Tape(t);
    memcpy(buffer, tape.data.data(), sizeof(uint64_t)*tape.data.size());
}

@end
