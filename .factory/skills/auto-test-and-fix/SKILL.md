---
name: auto-test-and-fix
description: End-to-end test → analyze → propose fix → verify loop (production safe).
---

Steps:
1. Execute tests via pwsh: pytest --tb=no -q
2. If pass → output SUCCESS
3. If fail → invoke tester droid for root cause
4. Propose exact coder delegation with file + line + expected behavior
5. After coder edit → re-run test until pass or max 3 attempts

Output:
TEST_RUN_RESULT: PASS/FAIL
ITERATION: N/3
CURRENT_FAILURE: ...
PROPOSED_FIX_DELEGATION: coder "Modify X in file Y to Z"
VERIFICATION_PLAN: next test command

## Coverage Threshold Checking (覆盖率阈值检查)

### 配置覆盖率阈值

```yaml
coverage:
  minimum: 80.0
  threshold_strict: true
  fail_below_threshold: true
  file_level_minimum: 60.0
  excluded_patterns:
    - "*/tests/*"
    - "*/__init__.py"
    - "*/migrations/*"
```

### 覆盖率检查规则

1. **整体覆盖率**: 必须不低于80%
2. **单文件覆盖率**: 关键文件不低于60%
3. **严格模式**: 启用时，任何未达标都会失败
4. **增量检查**: 新增代码必须100%覆盖

### 覆盖率测试命令

```bash
# Python (pytest + coverage)
pytest --cov=. --cov-report=xml --cov-report=html --cov-fail-under=80

# Node.js (jest with coverage)
jest --coverage --coverageThreshold='{"global":{"lines":80}}'

# Java (JaCoCo)
mvn clean test jacoco:check
```

## Performance Regression Detection (性能回归检测)

### 性能基线建立

```python
# 性能基线示例
performance_baseline:
  test_api_endpoint:
    max_duration: 200ms
    avg_duration: 150ms
    p95_duration: 180ms
    memory_increase: 10MB

  test_database_query:
    max_duration: 500ms
    query_count: 5
    rows_affected: <1000
```

### 回归检测规则

```
## 检测维度

1. 响应时间
   - 最大响应时间超过基线X% → FAIL
   - P95响应时间增加超过Y% → WARN

2. 资源使用
   - 内存使用超过基线阈值 → FAIL
   - CPU使用持续超过阈值 → WARN

3. 吞吐量
   - 请求/秒下降超过Z% → FAIL
   - 错误率增加 → FAIL

## 阈值配置
- 严格模式: 超过5%即失败
- 标准模式: 超过10%即失败
- 宽松模式: 超过20%即警告
```

### 性能测试命令

```python
# pytest-benchmark 示例
@pytest.mark.benchmark(
    min_rounds=5,
    max_time=1.0,
    warmup=True
)
def test_function_performance(benchmark):
    result = benchmark(target_function)
    assert result is not None

# 断言性能阈值
assert benchmark.stats['mean'] < 0.1  # 100ms
```

## Multi-Framework Support (多框架支持)

### 支持的测试框架

#### Python
```bash
# pytest
pytest --tb=short -v
pytest --cov=. --cov-fail-under=80
pytest -k "test_specific" --lf  # 只跑上次失败的

# unittest
python -m unittest discover -s tests
python -m unittest tests.test_module
```

#### JavaScript/TypeScript (Jest)
```bash
jest
jest --coverage
jest --coverageThreshold='{"global":{"branches":80,"functions":80,"lines":80,"statements":80}}'
jest --testNamePattern="test name"
jest --onlyChanged
```

#### Node.js (Mocha)
```bash
mocha
mocha --reporter json --reporter-options output=report.json
mocha --require source-map-support/register
```

#### Go
```bash
go test ./...
go test -v -race ./...
go test -cover -coverprofile=coverage.out ./...
go test -bench=. -benchmem ./...
```

#### Playwright (端到端测试)
```bash
# 运行所有测试
npx playwright test

# 指定浏览器
npx playwright test --project=chromium
npx playwright test --project=webkit

# 运行特定测试
npx playwright test test-example.spec.ts

# 调试模式
npx playwright test --debug

# 带覆盖率
npx playwright test --coverage
```

#### 其他框架
```bash
# Ruby (RSpec)
rspec --format documentation

# Java (JUnit)
mvn test
gradle test

# .NET (xUnit)
dotnet test
```

### 框架自动检测

```python
def detect_test_framework(project_path):
    """自动检测项目使用的测试框架"""
    if os.path.exists('pytest.ini'):
        return 'pytest'
    elif os.path.exists('jest.config.js'):
        return 'jest'
    elif os.path.exists('go.mod'):
        return 'gotest'
    elif os.path.exists('package.json'):
        return detect_js_framework()
    # ...
```

## Enhanced Error Classification (增强错误分类)

### 错误分类体系

```
## 按严重程度分类

### Critical (严重)
- 崩溃/异常终止
- 数据损坏/丢失
- 安全漏洞暴露
- 资源耗尽

### High (高)
- 核心功能不可用
- 性能严重下降
- 数据不一致
- 超时频繁

### Medium (中)
- 边缘场景失败
- 非核心功能问题
- UI/UX缺陷
- 偶发错误

### Low (低)
- 日志/警告信息
- 建议性改进
- 文档问题
- 代码风格
```

### 按类型分类

```
## 错误类型

### 1. 运行时错误
- TypeError/AttributeError/ValueError (Python)
- NullPointerException (Java)
- ReferenceError (JavaScript)
- 空指针/数组越界

### 2. 断言错误
- 预期值不匹配
- 条件不符
- 状态错误

### 3. 超时错误
- 请求超时
- 等待超时
- 锁超时

### 4. 配置错误
- 环境变量缺失
- 配置文件错误
- 依赖版本不兼容

### 5. 网络错误
- 连接失败
- DNS解析错误
- Socket错误

### 6. 数据库错误
- 连接失败
- 查询错误
- 约束违反
```

### 错误分析模板

```json
{
  "error_type": "AssertionError",
  "severity": "high",
  "message": "Expected 200, got 500",
  "stack_trace": "...",
  "test_file": "tests/api/test_users.py",
  "test_function": "test_create_user",
  "line_number": 42,
  "code_snippet": "...",
  "possible_causes": [
    "Invalid input data",
    "Database connection issue",
    "Authentication failure"
  ],
  "suggested_fixes": [
    "Add input validation",
    "Check database connection",
    "Verify authentication tokens"
  ],
  "related_files": [
    "src/api/users.py",
    "src/db/connection.py"
  ]
}
```

## Enhanced Iteration Strategy (增强迭代策略)

### 迭代规则

```
## 最大循环次数
MAX_ITERATIONS = 3

## 迭代策略

### 第1次迭代
- 目标: 快速修复明显错误
- 策略: 直接修复，最小改动
- 超时: 5分钟

### 第2次迭代
- 目标: 深入分析根因
- 策略: 查看相关代码，系统性修复
- 超时: 10分钟

### 第3次迭代
- 目标: 全面重构（如需要）
- 策略: 考虑设计问题，必要时重构
- 超时: 15分钟

### 超出最大迭代
- 标记失败
- 生成详细报告
- 建议人工介入
```

### 迭代过程

```python
iteration_state = {
    'iteration': 0,
    'previous_failures': [],
    'fixes_attempted': [],
    'new_failures': False,
    'same_error': False,
    'regression_detected': False
}

def run_iteration():
    iteration_state['iteration'] += 1

    # 运行测试
    result = execute_tests()

    if result == 'PASS':
        return 'SUCCESS'

    # 分析失败
    failure = analyze_failure(result)

    # 检测回归
    if check_regression(iteration_state, failure):
        iteration_state['regression_detected'] = True
        return 'REGRESSION_DETECTED'

    # 检测相同错误
    if is_same_error(failure, iteration_state['previous_failures']):
        iteration_state['same_error'] = True

    # 生成修复建议
    fix = propose_fix(failure)
    iteration_state['fixes_attempted'].append(fix)
    iteration_state['previous_failures'].append(failure)

    return 'CONTINUE'
```

### 回归检测

```python
def check_regression(state, current_failure):
    """检测是否引入了新的失败"""
    if not state['previous_failures']:
        return False

    failed_before = {f['test_id'] for f in state['previously_failed']}
    failed_now = {f['test_id'] for f in current_failure['failures']}

    new_failures = failed_now - failed_before

    return len(new_failures) > 0
```

## Enhanced Workflow

### 1. Initial Test Run
```bash
# 运行测试并收集结果
[framework_command] --output-format=json --output=results.json
```

### 2. Analyze Results
```
- Parse test results
- Check coverage thresholds
- Detect performance regressions
- Classify errors
```

### 3. If Pass → Success
```
- Generate success report
- Verify coverage
- Check performance
```

### 4. If Fail → Root Cause Analysis
```
- Invoke tester droid
- Stack trace analysis
- Related code inspection
- Error classification
```

### 5. Propose Fix
```
- Identify specific location (file:line)
- Describe expected behavior
- Suggest implementation
```

### 6. Apply Fix (via coder)
```
- Delegate to coder droid
- Wait for completion
```

### 7. Re-Test
```
- Re-run tests
- Check for regression
- Update iteration count
```

### 8. Loop or Exit
```
if iteration < max_iterations and not success:
    continue
else:
    generate_final_report()
```

## Enhanced Output Format

```markdown
# 测试修复报告

## 测试执行

### 基本信息
- 框架: [pytest/jest/gotest/playwright]
- 命令: [执行的命令]
- 时间戳: [timestamp]
- 环境: [test/staging/production]

### 测试结果
TEST_RUN_RESULT: PASS/FAIL

#### 统计信息
- 总测试数: [X]
- 通过: [X]
- 失败: [X]
- 跳过: [X]
- 耗时: [X min]

### 覆盖率报告
COVERAGE_RESULT: PASS/FAIL

#### 覆盖率统计
- 整体覆盖率: [X%] (阈值: 80%)
- 行覆盖率: [X%]
- 分支覆盖率: [X%]
- 函数覆盖率: [X%]

#### 低于阈值的文件
- [file1]: [X%]
- [file2]: [X%]

### 性能检查
PERFORMANCE_RESULT: PASS/WARN/FAIL

#### 性能指标
- 平均响应时间: [Xms] (基线: [Xms])
- P95响应时间: [Xms] (基线: [Xms])
- 内存使用: [XMB] (基线: [XMB])

#### 回归检测
- [测试名称]: [指标] 增加 [X%]

### 迭代状态
ITERATION: [N/3]
MAX_ITERATIONS: 3

#### 迭代历史
- 迭代1: [原因] → [修复]
- 迭代2: [原因] → [修复]
- 迭代3: [原因] → [修复]

## 失败分析

### 当前失败
CURRENT_FAILURE:

#### 严重程度: [critical/high/medium/low]
#### 错误类型: [error_classification]

#### 失败的测试
1. [test_name]
   - 文件: [file:line]
   - 错误: [error_message]
   - 堆栈: [stack_trace]

2. [test_name]
   - 文件: [file:line]
   - 错误: [error_message]

#### 根本原因
- **直接原因**: [description]
- **深层原因**: [analysis]
- **相关代码**: [references]

## 修复建议

### 立即修复
PROPOSED_FIX_DELEGATION: coder "Modify X in file Y to Z"

#### 具体更改
```diff
- [old code]
+ [new code]
```

#### 验证计划
VERIFICATION_PLAN:
- 命令: [next_test_command]
- 预期结果: [expected_behavior]
- 重新测试: [yes/no]

### 替代方案
1. [option 1]: [description]
2. [option 2]: [description]

## 回归检测
REGRESSION_DETECTED: yes/no

#### 新失败的测试
- [test_name] (之前通过)

#### 性能回归
- [metric]: 增加 [X%]

## 后续行动

### 如果成功
- 更新文档
- 提交代码
- 标记完成

### 如果失败
- 需要人工介入: yes/no
- 转交: [团队/个人]
- 说明: [详细描述]

## 总结
- 最终状态: [SUCCESS/FAILED/MANUAL_REVIEW]
- 总迭代次数: [X]
- 总耗时: [X min]
- 建议: [overall_recommendation]
```

## Analysis Checklist

Before completing:
- [ ] Selected correct test framework
- [ ] Executed tests successfully
- [ ] Checked coverage thresholds
- [ ] Ran performance checks
- [ ] Analyzed failures with root cause
- [ ] Classified errors correctly
- [ ] Verified no regression
- [ ] Respected iteration limit
- [ ] Generated comprehensive report
- [ ] Suggested concrete fixes

## Best Practices

1. **Always Run Tests First**: Establish baseline before changes
2. **Fix Root Cause, Not Symptoms**: Address the underlying issue
3. **Check for Regression**: Ensure new fixes don't break existing tests
4. **Respect Iteration Limits**: Don't waste cycles on unfixable issues
5. **Document Everything**: Keep detailed logs of attempts
6. **Use Appropriate Fix Granularity**: Small, focused changes are better
7. **Verify After Fix**: Always re-run tests after applying fix
8. **Know When to Escalate**: Recognize when manual help is needed
