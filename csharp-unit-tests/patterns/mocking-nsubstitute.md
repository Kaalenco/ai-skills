# Pattern: Mocking with NSubstitute

Use when the test project references `NSubstitute`. Works the same with MSTest and xUnit v3.

Prefer real objects for DTOs and value types. Substitute only dependencies behind an
interface (repositories, clients, clocks, other services).

## Cheat sheet

```csharp
using NSubstitute;
using NSubstitute.ExceptionExtensions;

// Create
var repository = Substitute.For<IOrderRepository>();

// Configure a return value
repository.GetOrder(orderId, Arg.Any<CancellationToken>()).Returns(order);

// Argument matchers
repository.GetOrder(Arg.Is<OrderId>(id => id.Value > 0), Arg.Any<CancellationToken>()).Returns(order);

// Throw
repository.GetOrder(orderId, Arg.Any<CancellationToken>()).Throws(new InvalidOperationException("boom"));

// Async returns -- Returns() works directly on Task<T> / ValueTask<T>
repository.Complete(Arg.Any<CancellationToken>()).Returns(true);

// Verify a call happened (exactly once)
repository.Received(1).Complete(Arg.Any<CancellationToken>());

// Verify a call did not happen
repository.DidNotReceive().Complete(Arg.Any<CancellationToken>());

// Capture an argument for detailed assertions
Order? saved = null;
repository.Add(Arg.Do<Order>(o => saved = o));
```

## Key rules

- Name the substitute after its role (`repository`, `clock`), not `mock` or `fake`.
- Verify interactions (`Received`) only when the call itself is the observable outcome,
  e.g. `Complete()` on a unit of work. Otherwise assert on returned results.
- Do not substitute concrete classes -- NSubstitute can only intercept virtual members, so
  non-virtual calls silently run the real code. The `NSubstitute.Analyzers.CSharp` package
  flags this; add it to the test project.
