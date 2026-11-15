// Prints the hashes clipper/libcxx_sort_wbtest.mbt expects: libc++'s std::sort on keys with ties, the order of
// the equal ones hashed. Usage: clang++ -std=c++17 -stdlib=libc++ -O1 libcxx-sort-cases.cpp -o cases && ./cases
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <vector>

struct Item {
  uint32_t key;
  uint32_t index;
};

int main() {
  const uint32_t sizes[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 12, 23, 24, 25, 31, 32, 33, 64, 100, 128, 129, 200, 500, 1000, 5000};
  uint32_t seed = 12345;
  std::printf("[");
  for (uint32_t n : sizes) {
    for (uint32_t pattern = 0; pattern < 7; pattern++) {
      std::vector<Item> items(n);
      for (uint32_t i = 0; i < n; i++) {
        seed = seed * 1103515245u + 12345u;
        uint32_t r = seed >> 8;
        uint32_t key = pattern == 0 ? r % 4 : pattern == 1 ? r % (n / 4 + 1) : pattern == 2 ? r : pattern == 3 ? i / 3 : pattern == 4 ? (n - i) / 3 : pattern == 5 ? 7 : (i < n / 2 ? i : n - i) / 2;
        items[i] = {key, i};
      }
      std::sort(items.begin(), items.end(), [](const Item& a, const Item& b) { return a.key < b.key; });
      uint32_t h = 0;
      for (const Item& item : items) h = h * 31u + item.index;
      std::printf("%uU, ", h);
    }
  }
  std::printf("]\n");
  return 0;
}
