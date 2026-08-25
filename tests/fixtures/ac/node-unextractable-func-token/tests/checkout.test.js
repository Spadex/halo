// AC-1 走 jest 参数化写法。函数名提取正则要的是紧跟左括号的形态，
// 参数化写法在名字和左括号之间隔了一个 `.each`，于是提取不到任何 token。
// 这一行就是被测的陷阱，改动它等于改掉断言的含义。
it.each([[1], [2]])("AC-1 charges every line item %i", (n) => {
  expect(n).toBeGreaterThan(0);
});

// AC-2 是普通写法，提取得到 token。它守的是反向：修复不能把正常识别一起打坏。
test("AC-2 rejects an empty cart", () => {
  expect(true).toBe(true);
});
