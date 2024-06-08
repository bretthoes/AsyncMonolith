# AsyncMonolith ![Logo](AsyncMonolith/logo.png)
[![NuGet](https://img.shields.io/nuget/v/AsyncMonolith)](https://www.nuget.org/packages/AsyncMonolith)

AsyncMonolith is a lightweight dotnet library that facillitates simple asynchronous processes in monolithic dotnet apps.

# Overview ✅

- Makes building event driven architectures simple
- Produce messages transactionally along with changes to your domain
- Messages are stored in your DB context so you have full control over them
- Supports running multiple instances / versions of your application
- Schedule messages to be processed using Chron expressions
- Automatic message retries
- Automatically routes messages to multiple consumers
- Keep your infrastructure simple, It only requires a dotnet API and database
- Makes it very easy to write unit / integration tests

# Support 🛟
Need help? Ping me on [linkedin](https://www.linkedin.com/in/timmoth/) and I'd be more then happy to jump on a call to debug, help configure or answer any questions.

## Warnings ⚠️
- Efcore does not natively support row level locking, this makes it possible for two instances of your app to compete over the next available message to be processed, potentially wasting cycles. For this reason it is reccomended that you only use `AsyncMonolith.Ef` when you are running a single instance of your app OR for development purposes. Using `AsyncMonlith.PostgreSql` or `AsyncMonolith.MySql` will allow the system to lock rows ensuring they are only retrieved and processed once.
- Test your desired throughput

### 'Don't use a database as a queue' - maybe
- Async Monolith is not a guaranteed replacement for a message broker, there are many reasons why you may require one.
- I'd reccomend watching this [video](https://www.youtube.com/watch?v=DOaDpHh1FsQ) by Derik Comartin or [this one](https://www.youtube.com/watch?v=_r2DaswYPjM) by Chris Patterson before deciding to use Async Monolith.

# Dev log 📒

Make sure to check this table before updating the nuget package in your solution, you may be required to add an `dotnet ef migration`.
| Version      | Description | Migration Required |
| ----------- | ----------- |----------- |
| 1.0.9      | Split out Ef, PostgreSql, MySql into seperate packages | Yes |
| 1.0.8      | Added scheduled message batching | No |
| 1.0.7      | Added consumer message batching | No |
| 1.0.6      | Added concurrent processors | No |
| 1.0.5      | Added OpenTelemetry support   | No |
| 1.0.4      | Added poisoned message table   | Yes |
| 1.0.3      | Added mysql support   | Yes |
| 1.0.2      | Scheduled messages use Chron expressions   | Yes |
| 1.0.1      | Added Configurable settings    | No |
| 1.0.0      | Initial   | Yes |

# Message Handling Guide

## Producing Messages 📨

- **Transactional Persistence**: Produce messages along with changes to your `DbContext` before calling `SaveChangesAsync`, ensuring your domain changes and the messages they produce are persisted transactionally.
- **Deduplication**: By specifying a `insert_id` when producing messages the system ensures only one message with the same `insert_id` and `consumer_type` will be in the table at a given time. This is useful when you need a process to take place an amount of time after the first action in a sequence occured.

### Ef Example

The produce method when using pure Ef code will just add the messages directly to your DB context, calling `SaveChangesAsync` will ensure that the messages are inserted in the same transaction as your other domain updates.

  ```csharp
  // Publish 'UserDeleted' to be processed in 60 seconds
    await _producerService.Produce(new UserDeleted()
    {
      Id = id
    }, 60);
  await _dbContext.SaveChangesAsync(cancellationToken);
  ```
  
### MySql / PostgreSql Example

The produce method when using MySql or PostgreSQL makes use of `ExecuteSqlRawAsync`, if you want the messages to be inserted transactionally with your domain changes you must wrap all the changes in an explicit transaction.

  ```csharp
    await using var dbContextTransaction = await _dbContext.Database.BeginTransactionAsync(cancellationToken);

	...
	
	// Publish 'UserDeleted' to be processed in 60 seconds
    await _producerService.Produce(new UserDeleted()
    {
      Id = id
    }, 60);
	
  await _dbContext.SaveChangesAsync(cancellationToken);
  await dbContextTransaction.CommitAsync(stoppingToken);

  ```
  
## Scheduling Messages ⌛

- **Frequency**: Scheduled messages will be produced periodically by the `chron_expression` in the given `chron_timezone`
- **Transactional Persistence**: Schedule messages along with changes to your `DbContext` before calling `SaveChangesAsync`, ensuring your domain changes and the messages they produce are persisted transactionally.
- **Processing**: Schedule messages will be processed sequentially after they are made available by their chron job, at which point they will be turned into Consumer Messages and inserted into the `consumer_messages` table to be handled by their respective consumers.

  Example
  ```csharp
  // Publish 'CacheRefreshScheduled' every Monday at 12pm (UTC) with a tag that can be used to modify / delete related scheduled messages.
  _scheduledMessageService.Schedule(new CacheRefreshScheduled
    {
        Id = id
    }, "0 0 12 * * MON", "UTC", "id:{id}");
  await _dbContext.SaveChangesAsync(cancellationToken);
  ```
## Consuming Messages 📫

- **Independent Consumption**: Each message will be consumed independently by each consumer set up to handle it.
- **Periodic Querying**: Each instance of your app will periodically query the `consumer_messages` table for a batch of available messages to process.
  - The query takes place at the frequency defined by `ProcessorMaxDelay`, if a full batch is returned it will delay by `ProcessorMinDelay`.
- **Concurrency**: Each app instance can run multiple parallel consumer processors defined by `ConsumerMessageProcessorCount`, unless using `AsyncMonolith.Ef`.
- **Batching**: Consumer messages will be read from the `consumer_messages` table in batches defined by `ConsumerMessageBatchSize`. 
- **Idempotency**: Ensure your Consumers are idempotent, since they will be retried on failure. 
  
Example
```csharp
public class DeleteUsersPosts : BaseConsumer<UserDeleted>
{
    private readonly ApplicationDbContext _dbContext;

    public ValueSubmittedConsumer(ApplicationDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public override Task Consume(UserDeleted message, CancellationToken cancellationToken)
    {
        ...
		await _dbContext.SaveChangesAsync(cancellationToken);
    }
}
```
## Changing Consumer Payload Schema 🔀

- **Backwards Compatibility**: When modifying consumer payload schemas, ensure changes are backwards compatible so that existing messages with the old schema can still be processed.
- **Schema Migration**:
  - If changes are not backwards compatible, make the changes in a copy of the `ConsumerPayload` (with a different class name) and update all consumers to operate on the new payload.
  - Once all messages with the old payload schema have been processed, you can safely delete the old payload schema and its associated consumers.

## Consumer Failures 💢

- **Retry Logic**: Messages will be retried up to `MaxAttempts` times (with a `AttemptDelay` seconds between attempts) until they are moved to the `poisoned_messages` table.
- **Manual Intervention**: If a message is moved to the `poisoned_messages` table, it will need to be manually removed from the database or moved back to the `consumer_messages` table to be retried. Note that the poisoned message will only be retried a single time unless you set `attempts` back to 0.
- **Monitoring**: Periodically monitor the `poisoned_messages` table to ensure there are not too many failed messages.

## OpenTelemetry Support 📊

Ensure you add `AsyncMonolithInstrumentation.ActivitySourceName` as a source to your OpenTelemetry configuration if you want to receive consumer / scheduled processor traces.
```csharp
        builder.Services.AddOpenTelemetry()
            .WithTracing(x =>
            {
                if (builder.Environment.IsDevelopment()) x.SetSampler<AlwaysOnSampler>();

                x.AddSource(AsyncMonolithInstrumentation.ActivitySourceName);
                x.AddConsoleExporter();
            })
            .ConfigureResource(c => c.AddService("async_monolith.demo").Build());
```

# Quick start guide ▶️
(for a more detailed example look at the Demo project)

```csharp

    // Install the core package
    dotnet add package AsyncMonolith
	// Install the Db specific package
    dotnet add package AsyncMonolith.Ef
    dotnet add package AsyncMonolith.MySql
    dotnet add package AsyncMonolith.PostgreSql

    // Add Db Sets, and configure ModelBuilder
    public class ApplicationDbContext : DbContext
    {
        public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options) : base(options)
        {
        }

        public DbSet<ConsumerMessage> ConsumerMessages { get; set; } = default!;
        public DbSet<PoisonedMessage> PoisonedMessages { get; set; } = default!;
        public DbSet<ScheduledMessage> ScheduledMessages { get; set; } = default!;
		
		protected override void OnModelCreating(ModelBuilder modelBuilder)
		{
			modelBuilder.ConfigureAsyncMonolith();
			base.OnModelCreating(modelBuilder);
		}
    }

    // Register required services
    builder.Services.AddLogging();
    builder.Services.AddSingleton(TimeProvider.System);
	
	// Register AsyncMonolith using either:
	// services.AddEfAsyncMonolith
	// services.AddMySqlAsyncMonolith
	// services.AddPostgreSqlAsyncMonolith
	
    builder.Services.AddPostgreSqlAsyncMonolith<ApplicationDbContext>(Assembly.GetExecutingAssembly(), new AsyncMonolithSettings()
    {
        AttemptDelay = 10, // Seconds before a failed message is retried
        MaxAttempts = 5, // Number of times a failed message is retried 
        ProcessorMinDelay = 10, // Minimum millisecond delay before the next batch is processed
        ProcessorMaxDelay = 1000, // Maximum millisecond delay before the next batch is processed
		ProcessorBatchSize = 5, // The number of messages to process in a single batch
        ConsumerMessageProcessorCount = 2, // The number of concurrent consumer message processors to run in each app instance
        ScheduledMessageProcessorCount = 1, // The number of concurrent scheduled message processors to run in each app instance
    });
	
    // Define Consumer Payloads
    public class ValueSubmitted : IConsumerPayload
    {
        [JsonPropertyName("value")]
        public required double Value { get; set; }
    }

    // Define Consumers
    public class ValueSubmittedConsumer : BaseConsumer<ValueSubmitted>
    {
        private readonly ApplicationDbContext _dbContext;
        private readonly ProducerService<ApplicationDbContext> _producerService;
    
        public ValueSubmittedConsumer(ApplicationDbContext dbContext, ProducerService<ApplicationDbContext> producerService)
        {
            _dbContext = dbContext;
            _producerService = producerService;
        }
    
        public override Task Consume(ValueSubmitted message, CancellationToken cancellationToken)
        {
            ...
	    await _dbContext.SaveChangesAsync(cancellationToken);
        }
    }

    // Produce / schedule messages
    private readonly ProducerService<ApplicationDbContext> _producerService;
    private readonly ScheduledMessageService<ApplicationDbContext> _scheduledMessageService;

    await _producerService.Produce(new ValueSubmitted()
    {
      Value = newValue
    });

    _scheduledMessageService.Schedule(new ValueSubmitted
    {
        Value = Random.Shared.NextDouble() * 100
    }, "*/5 * * * * *", "UTC");
	
    await _dbContext.SaveChangesAsync(cancellationToken);

```

# Internals
![Logo](Diagrams/AsyncMonolith.svg)

## ProducerService
Resolves consumers for a given payload and writes messages to the `consumer_messages` table for processing.

## ScheduleService
Writes scheduled messages to the `scheduled_messages` table.

## DbSet: ConsumerMessage
Stores all messages awaiting processing by the `ConsumerMessageProcessor`.

## Dbset: ScheduledMessage
Stores all scheduled messages awaiting processing by the `ScheduledMessageProcessor`.

## DbSet: PoisonedMessage
Stores consumer messages that have reached `AsyncMonolith.MaxAttempts`, poisoned messages will then need to be manually moved back to the `consumer_messages` table or deleted.

## ConsumerMessageProcessor
A background service that periodically fetches available messages from the 'consumer_messages' table. Once a message is found, it's row-level locked to prevent other processes from fetching it. The corresponding consumer attempts to process the message. If successful, the message is removed from the `consumer_messages` table; otherwise, the processor increments the messages `attempts` by one and delays processing for a defined number of seconds (`AsyncMonolithSettings.AttemptDelay`). If the number of attempts reaches the limit defined by `AsyncMonolith.MaxAttempts`, the message is moved to the `poisoned_messages` table.

## ScheduledMessageProcessor
A background service that fetches available messages from the `scheduled_messages` table. Once found, each consumer set up to handle the payload is resolved, and a message is written to the `consumer_messages` table for each of them.

## ConsumerRegistry
Used to resolve all the consumers able to process a given payload, and resolve instances of the consumers when processing a message. The registry is populated on startup by calling `builder.Services.AddAsyncMonolith<ApplicationDbContext>(Assembly.GetExecutingAssembly());` which uses reflection to find all consumer & payload types.

## Notes 📋
- The background services wait for `AsyncMonolithSettings.ProcessorMaxDelay` seconds before fetching another batch of messages. If a full batch is fetched, the delay is reduced to `AsyncMonolithSettings.ProcessorMinDelay` seconds between cycles.
- Configuring concurrent consumer / scheduled message processors will throw a startup exception when using AsyncMonolith.Ef (due to no built in support for row level locking)

## Tests 🐞
- Some of the test rely on TestContainers to run against real databases, make sure you've got docker installed

## Demo
- Hit `https://localhost:60046/api/spam?count=1000` to see how performant AsyncMonolith is on your system. With 10 message batches and single processor instance I usually process (trivial) messages at <10ms each.
- The demo is setup to run against a PostgreSql database, make sure you've got docker installed

## Contributing 🙏

Contributions are welcome! Here’s how you can get involved:

1. **Fork the repository**: Click the "Fork" button at the top right of this page.
2. **Clone your fork**:
    ```bash
    git clone https://github.com/Timmoth/AsyncMonolith.git
    ```
3. **Create a branch**: Make your changes in a new branch.
    ```bash
    git checkout -b my-feature-branch
    ```
4. **Commit your changes**:
    ```bash
    git commit -m 'Add some feature'
    ```
5. **Push to the branch**:
    ```bash
    git push origin my-feature-branch
    ```
6. **Open a pull request**: Describe your changes and submit your PR.
