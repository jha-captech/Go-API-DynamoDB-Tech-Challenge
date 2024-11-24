# Part 2: REST API Walkthrough

## Table of Contents

- [Overview](#overview)
- [Project Structure](#project-structure)
- [Database Setup](#database-setup)
    - [Configure the Connection to the Database](#configure-the-connection-to-the-database)
    - [Load and Validate the Environment Variables](#load-and-validate-environment-variables)
    - [Creating a `run` function to initialize dependencies](#creating-a-run-function-to-initialize-dependencies)
    - [Connect to DynamoDB](#connect-to-dynamodb)
    - [Setting up User Model](#setting-up-user-model)
    - [Creating our User Service](#creating-our-user-service)
- [Service Setup](#service-setup)
    - [Handler setup](#handler-setup)
    - [Route Setup](#route-setup)
    - [Server setup](#server-setup-1)
    - [Adding a server to main.go](#adding-a-server-to-maingo)
- [Add Middleware](#add-middleware)
- [Generating Swagger Docs](#generating-swagger-docs)
- [Injecting the user service into the read user handler](#injecting-the-user-service-into-the-read-user-handler)
- [Hiding the read user response type](#hiding-the-read-user-response-type)
- [Reading the user and mapping it to a response](#reading-the-user-and-mapping-it-to-a-response)
- [Flesh out user CRUD routes / handlers](#flesh-out-user-crud-routes--handlers)
- [Input model validation](#input-model-validation)
- [Unit Testing](#unit-testing)
    - [Unit Testing Introduction](#unit-testing-introduction)
    - [Unit Testing in This Tech Challenge](#unit-testing-in-this-tech-challenge)
    - [Example: Handler unit test](#example-handler-unit-test)
    - [Example: Service unit test](#example-service-unit-test)
- [Next Steps](#next-steps)


## Overview

As previously mentioned, this challenge is centered around the use of the `net/http` library for
developing APIs. Our web server will connect to a DynamoDB instance in the backend. This
walkthrough will consist of a step-by-step guide for creating the REST API for the `users` table in
the database. By the end of the walkthrough, you will have endpoints capable of creating, reading,
updating, and deleting from the `users` table.

## Project Structure

By default, you should see the following file structure in your root directory

```
.
├── cmd/
│   └── api/
│       └── main.go
├── internal/
│   ├── configuration/
│   │   └── configuration.go
│   ├── handlers
│   │   └── handlers.go
│   ├── routes/
│   │   └── routes.go
│   ├── models
│   │   └── models.go
│   ├── middleware
│   │   └── middleware.go
│   └── services/
│       └── user.go
├── .gitignore
├── .env.local
├── docker-compose.yaml
├── Makefile
└── README.md
```

Before beginning to look through the project structure, ensure that you first understand the basics
of Go project structuring. As a good starting place, check
out [Organizing a Go Module](https://go.dev/doc/modules/layout) from the Go team. It is important to
note that one size does not fit all Go projects. Applications can be designed on a spectrum ranging
from very lean and flat layouts, to highly structured and nested layouts. This challenge will sit in
the middle, with a layout that can be applied to a broad set of Go applications.

The `cmd/` folder contains the entrypoint(s) for the application. For this Tech Challenge, we will
only need one entrypoint into the application, `api`.

The `cmd/api` folder contains the entrypoint code specific to setting up a webserver for our
application. This code should be very minimal and is primarily focused on initializing dependencies
for our application then starting the application.

The `internal/` folder contains internal packages that comprise the bulk of the application logic
for the challenge:

- `config` contains our application configuration
- `handlers` contains our http handlers which are the functions that execute when a request is sent
  to the application
- `models` contains domain models for the application
- `routes` contains our route definitions which map a URL to a handler
- `server` contains a constructor for a fully configured `http.Server`
- `services` contains our service layer which is responsible for our application logic

The `Makefile` contains various `make` commands that will be helpful throughout the project. We will
reference these as they are needed. Feel free to look through the `Makefile` to get an idea for
what's there or add your own make targets.

Now that you are familiar with the current structure of the project, we can begin connecting our
application to our database.

## Database Setup

We will first begin by setting up the database connection for our application.

### Configure the Connection to the Database

In order for the project to be able to connect to the DynamoDB instance we created and started during setup, we first need to handle
configuration. We will create a `.env` file to store environment variables. The values needed to connect to the database should already be there.

### Load and Validate Environment Variables

To handle loading environment variables into the application, we will utilize the [
`env`](https://github.com/caarlos0/env) package from `caarlos0` as well as the [
`godotenv`](https://github.com/joho/godotenv) package. You should have already installed these packages during setup.

The `env` package is used to parse values from our system environment variables and map them to properties on a
struct we've defined. `env` can also be used to perform validation on environment variables such as
ensuring they are defined and don't contain an empty value.

The `godotenv` package is used to load values from `.env` files into system environment variables. This allows
us to define these values in a `.env` file for local development.

We first need to create a `.env` file. To do
this, running the following command to make a copy of the `.env.local` file:

```bash
# copy the .env.local file to .env
cp .env.local .env
```
If you look inside the `.env` file, you should see the following environment variables. These will be used by our application:

```
DYNAMODB_ENDPOINT=http://localhost:8000
HOST=localhost
PORT=8080
LOG_LEVEL=DEBUG
```

If you need to add other environment variables, you can do so by adding them to this file.

Now, find the `internal/configuration/configuration.go` file. This is where we'll define the struct to contain our
environment variables.

Add the struct definition below to the file below the existing package definition:

```go
// Config holds the application configuration settings. The configuration is loaded from
// environment variables.
type Configuration struct {
	DynamoEndpoint string     `env:"DYNAMODB_ENDPOINT,required"`
	Host           string     `env:"HOST,required"`
	Port           string     `env:"PORT,required"`
	LogLevel       slog.Level `env:"LOG_LEVEL,required"`
}
```

Note how we use struct tags to define the environment variable name and whether it is required for each field on the struct.  

Now, add the following function to the file below the `Configuration` struct:

```go
// New loads Configuration from environment variables and a .env file, and returns a
// Config struct or error.
func New() (Configuration, error) {
	// Load values from a .env file and add them to system environment variables.
	// Discard errors coming from this function. This allows us to call this
	// function without a .env file which will by default load values directly
	// from system environment variables.
	_ = godotenv.Load()
	 // Once values have been loaded into system env vars, parse those into our
	// configuration struct and validate them returning any errors.
	cfg, err := env.ParseAs[Config]()
	if err != nil {
		return Config{}, fmt.Errorf("[in configuration.New] failed to parse configuration: %w", err)
	}
	 return cfg, nil
}
```

In the above code, we created a function called `New()` that is responsible for loading the
environment variables from the `.env` file, validating them, and mapping them into our `Config`
struct. 

The `New` naming convention is widely established in Go, and is used when we are returning an
instance of an object from a package that shares the same name. Such as a `Config` object being
returned from a `config` package.

Note that we are using an underscore `_` to discard any possible errors from `godotenv.Load()` since we don't really care if there is an error and won't be handling the error if one was returned. Explicitly discarding errors when you don't want to handle them is considered a best practice as it signals to others that you meant to do this instead of just having forgotten to handle it.

### Creating a `run` function to initialize dependencies

Now that we can load config, let's take a step back and make an update to our `cmd/api/main.go`
file. One quirk of Go is that our `func main` can't return anything. Wouldn't it be nice if we could
return an error or a status code from `main` to signal that a dependency failed to initialize? We're
going to steal a pattern popularized by Matt Ryer to do exactly that.

First, in `cmd/api/main.go` we're going to add the `run` function below the `main()` function definition. It should contain logic to call `config.New()` and initialize a logger. The `run()` function will be responsible for initializing all our dependencies and starting our application:

```go
func run(ctx context.Context) error {
	// Load and validate environment configuration
	cfg, err := config.New()
	if err != nil {
		return fmt.Errorf("[in main.run] failed to load configuration: %w", err)
	}
    
	// Create a structured logger, which will print logs in json format to the
	// writer we specify.
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: cfg.LogLevel,
	}))
	
	return nil
}
```

Next, we'll update `func main` to look like this:

```go
func main() {
	ctx := context.Background()
	if err := run(ctx); err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "server encountered an error: %s\n", err)
		os.Exit(1)
	}
}
```

Now our `main` function is only responsible for calling `run` and handling any errors that come from
it. And our `run` function is responsible for initializing dependencies and starting our
application. This consolidates all our error handling to a single place, and it allows us to write
unit tests for the `run` function that assert proper outputs.

For more information on this pattern see this
excellent [blog post](https://grafana.com/blog/2024/02/09/how-i-write-http-services-in-go-after-13-years/)
by Matt Ryer.

### Connect to DynamoDB

Next, we'll connect our application to our DynamoDB instance. We'll leverage the `run` function we
just created as the spot to load our variables and initialize this connection.

To initialize our connection we're going to use the `aws-sdk-go-v2` package and some of its sub packages. You should have already installed these packages during setup.

First, in `cmd/api/main.go`, lets update `run`. Since connection to the database is just startup logic, we put it here instead of in its own package. Add the bellow code to the `run` function after to configuration and logger setup logic:

```go
// connect to dynamoDB
logger.InfoContext(ctx, "connecting to DynamoDB")
awscfg, err := config.LoadDefaultConfig(ctx)
if err != nil {
	return fmt.Errorf("[in main.run] failed to load configuration: %w", err)
}

client := dynamodb.NewFromConfig(awscfg, func(options *dynamodb.Options) {
	options.BaseEndpoint = aws.String(cfg.DynamoEndpoint)
})

// list all tables in db (we will delete this later)
result, err := client.ListTables(ctx, &dynamodb.ListTablesInput{})
if err != nil {
	return fmt.Errorf("[in main.run] failed to list tables: %w", err)
}

fmt.Println("Tables:")
for _, tableName := range result.TableNames {
	fmt.Printf("* %s\n", tableName)
}

return nil
```
Note that we have added some temporary code to print out all tables inside our DynamoDB instance. We will delete this in a few minutes, but for now, it will help us verify that we are able to connect to the database.

At this point, you can now test to see if your application is able to successfully connect to DynamoDB. To do so, open a terminal in the project root directory and run the bellow command. You should see logs indicating you connected to the database.

```bash
go run cmd/api/main.go
```

You should see the following output in the terminal:

```
Tables:
* BlogContent
```

Congrats! You have managed to connect to your DynamoDB instance from your application.

> Note: Before we continue, you can remove the temporary code that lists all tables in the database.

### Setting up User Model

Before we go any further, lets discuss DynamoDB and how it differs from a traditional SQL database. 
DynamoDB is a NoSQL database, which means it doesn't use tables, rows, and columns like a traditional 
SQL database. Instead, it uses tables, items, and attributes. An item is a single record in a table, 
and an attribute is a single piece of data in an item.

We also need to discus how we interact with DynamoDB using the `aws-sdk-go-v2` package. The `aws-sdk-go-v2` 
package provides a `dynamodb` package that contains a `Client` struct that we can use to interact with 
DynamoDB. The `Client` struct has methods that correspond to the various DynamoDB operations such as 
`Query`, `GetItem`, `PutItem`, `UpdateItem`, and `DeleteItem`. Each of these methods returns a specific 
output struct that contains both the data returned from the database and metadata about the request.

The `aws-sdk-go-v2` package also provides a `feature/dynamodb/attributevalue` package that we can use 
to convert Go structs to and from the `types.AttributeValue` struct that is used to represent data in 
DynamoDB. This package provides a `MarshalMap` function that can be used to convert a Go struct to a 
map of `types.AttributeValue` and an `UnmarshalMap` function that can be used to convert a map of 
`types.AttributeValue` to a Go struct. Its also worth noting that there are other marshalling functions 
the package provides that can be used to convert Go structs to and from other types of data.

In order to use the `attributevalue` package, we need to define Go structs that represent the data in 
the database. We use struct tags on our modules to tell the sdk what fields in the struct correspond 
to what attributes in the database.

With that context in mind, lets start creating our models.

First, lets create a base struct that will hold some of the DynamoDB specific information that we 
will need to interact with the database. In the `internal/models` package, create a new file called 
`dynamodb_bas.go` and add the following code:

```go
package models

type DynamoDBBase struct {
	PK     string `dynamodbav:"PK"`
	SK     string `dynamodbav:"SK"`
	GSI1PK string `dynamodbav:"GSI1PK"`
	GSI1SK string `dynamodbav:"GSI1SK"`
}
```

We will be embedding this struct in our other models so that these values are available to all of 
them. We will also talk more about what these values mean later

---

Let's take a step back for a second. If we look at our database using the NoSQL Workbench, we can see 
that we have several ID columns for our different entity types. These IDs are UUIDs. In Go, we will 
often use the `github.com/google/uuid` package to work with UUIDs. This package provides a `UUID` 
struct that can be used to represent a UUID. However, this will introduce a new problem for us here. 
While the `uuid` package implements the `Marshaler` and `Unmarshaler` interfaces from multiple other 
package, it does not implement the `Marshaler` and `Unmarshaler` interfaces from the 
`aws-sdk-go-v2/feature/dynamodb/attributevalue` package. This means that we will need to create our 
own UUID type that extends the `uuid` package and also implement these interfaces ourselves in order 
to use UUIDs in our models.

To do this, create a new file called `uuid.go` in the `internal/models` package and add the following code:

```go
package models

import (
	"fmt"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/google/uuid"
)

// UUID is a custom type that wraps a UUID and implements the Unmarshaler
// interface from the
// `github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue` package. It
// can be used to unmarshal a UUID from a DynamoDB attribute value.
type UUID struct {
	uuid.UUID
}

// UnmarshalDynamoDBAttributeValue unmarshals a UUID from a DynamoDB attribute
// value. It implements the attributevalue.Marshaler interface.
func (u *UUID) UnmarshalDynamoDBAttributeValue(av types.AttributeValue) error {
	s, ok := av.(*types.AttributeValueMemberS)
	if !ok {
		return fmt.Errorf("expected AttributeValueMemberS, got %T", av)
	}

	id, err := uuid.Parse(s.Value)
	if err != nil {
		return err
	}

	*u = UUID{UUID: id}
	return nil
}

// MarshalDynamoDBAttributeValue marshals a UUID into a DynamoDB attribute value.
// It implements the attributevalue.Marshaler interface.
func (u *UUID) MarshalDynamoDBAttributeValue() (types.AttributeValue, error) {
	return &types.AttributeValueMemberS{Value: u.UUID.String()}, nil
}
```

Let's go over what this code does:
- We define a new type called `UUID` that embeds the `uuid.UUID` struct from `github.com/google/uuid`. 
- Next we implicitly implement the `Unmarshaler` interface from the `aws-sdk-go-v2/feature/dynamodb/attributevalue` package with the `UnmarshalDynamoDBAttributeValue` method. This method is used to convert a `types.AttributeValue` to a `UUID` when unmarshalling data from the database.
- Next we implement the `Marshaler` interface from the `aws-sdk-go-v2/feature/dynamodb/attributevalue` with the `MarshalDynamoDBAttributeValue` method package. This method is used to convert a `UUID` to a `types.AttributeValue` when marshalling data to be added to the database.

This custom type that extends the `uuid` package and implements the `Marshaler` and `Unmarshaler` interfaces from the `aws-sdk-go-v2/feature/dynamodb/attributevalue` package will allow us to use UUIDs in our models and get proper marshaling and unmarshalling.

---

Before we go on, we need to take a quick detour to talk about table design in DynamoDB. DynamoDB
is a NoSQL database, which means it doesn't use tables, rows, and columns like a traditional SQL
database. Instead, it uses a key-value and document-based data model.

In DynamoDB, a table is a collection of items, and each item is a collection of attributes. Each
item is identified by a primary key, which is a unique attribute than can either be a single
partition key or composite key made up of partition key and sort key. In our case, we are using
a single table design, which means that we are storing multiple entity types in a single table.
To accomplish this, we are using a composite primary key and a composite sort key. The primary
key, named `PK`, is a combination of the string `USER#` and the user's ID. The primary key is used to
uniquely identify the item in the table. The sort key, named `SK`, is also a combination of the string
`USER#` and the user's ID. The sort key is used to sort items with the same primary key. In this
case, it is the same as the primary key, but this is not always the case for the other entity
types in the table. We will look at this more later. For now, we will just be working with the
`User` entity.

One last thing to note is that we have defined our primary key and sort key as fields on the 
DynamoDBBase struct. This is because we will be embedding this struct in our other models so 
that these values are available to all of them.

New, lets create our first entity model. In the `internal/models` package, create a new file 
called `user.go` and add the following code:

```go
package models

type User struct {
	DynamoDBBase
	ID       UUID   `dynamodbav:"user_id"`
	Name     string `dynamodbav:"name"`
	Email    string `dynamodbav:"email"`
	Password string `dynamodbav:"password"`
}
```
Note how we are embedding the `DynamoDBBase` struct in the `User`struct. This will allow us to 
access the fields in the `DynamoDBBase` struct from the `User` struct.

If you are interested, you can read more about embedding in Go [here](https://gobyexample.com/struct-embedding).

Last, lets delete the `models.go` file in the models package as we won't be using this project.

### Creating our User Service

Now that we have talked about our data model, we can start creating our service layer. Our 
service layer is where all of our application logic (including database access) will live. It's 
important to remember that there are many ways to structure Go applications. We're following a 
very basic layered architecture that places most of our logic and dependencies in a services 
package. This allows our handlers to focus on request and response logic, and gives us a single 
point to find application logic.

Start by adding the following struct, constructor function, and methods to the 
`internal/services/users.go` file. This file will hold the definitions for our user service:

```go
// UsersService is a service capable of performing CRUD operations for
// models.User models.
type UsersService struct {
	logger *slog.Logger
	client *dynamodb.Client
}

// NewUsersService creates a new UsersService and returns a pointer to it.
func NewUsersService(logger *slog.Logger, client *dynamodb.Client) *UsersService {
	return &UsersService{
		logger: logger,
		client: client,
	}
}
// CreateUser attempts to create the provided user, returning a fully hydrated
// models.User or an error.
func (s *UsersService) CreateUser(ctx context.Context, user models.User) (models.User, error) {
	return models.User{}, nil
}

// ReadUser attempts to read a user from the database using the provided id. A
// fully hydrated models.User or error is returned.
func (s *UsersService) ReadUser(ctx context.Context, id uint64) (models.User, error) {
	return models.User{}, nil
}

// UpdateUser attempts to perform an update of the user with the provided id,
// updating, it to reflect the properties on the provided patch object. A
// models.User or an error.
func (s *UsersService) UpdateUser(ctx context.Context, id uint64, patch models.User) (models.User, error) {
	return models.User{}, nil
}

// DeleteUser attempts to delete the user with the provided id. An error is
// returned if the delete fails.
func (s *UsersService) DeleteUser(ctx context.Context, id uint64) error {
	return nil
}

// ListUsers attempts to list all users in the database. A slice of models.User
// or an error is returned.
func (s *UsersService) ListUsers(ctx context.Context, id uint64) ([]models.User, error) {
	return []models.User{}, nil
}
```

We've stubbed out a basic `UsersService` capable of performing CRUD on our User model. Next we'll
flesh out the `ReadUser` method.

First, add this sentinel error to the top of the file:

```go
var ErrNotFound = fmt.Errorf("item not found")
```

We can use sentinel errors (also called named errors) to represent specific error conditions in our application and transfer that information across API boundaries. In this case, we will use this error to represent the case where a user is not found in the database and let our handlers know that they should return a 404 status code.

> [!CAUTION]
> Sentinel errors can be an important pattern to use in Go, but they can also be very easily overused. Be sure to use them judiciously and only when they make sense. A good rule of thumb is to only use them when you need to communicate specific error conditions across API boundaries.

Next, update the `ReadUser` method to below:

```go
// ReadUser attempts to read a user from the database using the provided id. A
// fully hydrated models.User or error is returned.
func (s *UsersService) ReadUser(ctx context.Context, id uuid.UUID) (models.User, error) {
	s.logger.DebugContext(ctx, "Reading user", "id", id)

	// get item from DynamoDB by PK and SK
	result, err := s.client.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String("BlogContent"),
		Key: map[string]types.AttributeValue{
			"PK": &types.AttributeValueMemberS{
				Value: fmt.Sprintf("USER#%s", id.String()),
			},
			"SK": &types.AttributeValueMemberS{
				Value: fmt.Sprintf("USER#%s", id.String()),
			},
		},
	})
	if err != nil {
		return models.User{}, fmt.Errorf(
			"[in main.UsersService.ReadUser] failed to get item: %w",
			err,
		)
	}

	// handle item not found
	if result.Item == nil {
		return models.User{}, ErrNotFound
	}

	// Unmarshal the results into the models.User struct
	var user models.User
	if err = attributevalue.UnmarshalMap(result.Item, &user); err != nil {
		return models.User{}, fmt.Errorf(
			"[in main.UsersService.ReadUser] failed to unmarshal result: %w",
			err,
		)
	}

	return user, nil
}
```

Let's quickly walk through the structure of this method, as it will serve as a template for other
similar methods:

- We log a debug message indicating that we are reading a user with the provided ID.
- We call `client.GetItem` to query the database for the user with the provided ID. We pass in the
  table name and a map of the primary key and sort key to query the database. This method returns a single item from the database.
  - The primary key is a combination of the string `USER#` and the user's ID.
    - The primary key is used to uniquely identify the item in the table.
  - The sort key is also a combination of the string `USER#` and the user's ID.
    - The sort key is used to sort items with the same primary key. In this case it is the same as the primary key, but this is not the case.
- We check if the `result.Item` is `nil`, which means that the user was not found in the database. If this is the case, we return a sentinel error.
- We unmarshal the results into a `models.User` struct using the `attributevalue.UnmarshalMap` method.
  - This method is used to convert a map of `types.AttributeValue` to a struct. It is used to convert the response from the database into a struct that we can use in our application.
- We return the user or an error.

---

Now that you've implemented the `ReadUser` method, go through an implement the other CRUD methods on the service struct.

There are multiple ways that you can do this, and you have the freedom to approach this in the 
way that you feel most comfortable with. With that being said, here are a couple of things to keep 
in mind:
- Remember, the `BlogContent` table has been designed using single table design. This means that the database hase a single table and that table contains multiple entity types, in this case, users and blog posts. 
- The `BlogContent` table has also been designed in such a way that you should not need to use a `scan` action to complete any of the service methods. This is because scanning is an expensive operation that we want to avoid if possible when working in the real world.
- Inorder to discover how best to     retrieve the data for each method, you may need to look at the `BlogContent` table in the NoSQL Workbench to see how the data is structured. You can also build operations in the NoSQL Workbench to test how to retrieve the data you need.
- The `BlogContent` table has been built with two separate Global Secondary Indexes (GSI) to facilitate different access patterns. You will need to use some of these indexes to complete some of the service methods. You can read more about GSIs [here](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GSI.html).

If you get stuck, here are some helpful resources on working with `aws-sdk-go-v2`:
- [Amazon DynamoDB Examples Using the AWS SDK for Go](https://docs.aws.amazon.com/sdk-for-go/v1/developer-guide/using-dynamodb-with-go-sdk.html)
- [dynamodb Package Documentation](https://pkg.go.dev/github.com/aws/aws-sdk-go-v2/service/dynamodb)
- [Getting started with DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GettingStartedDynamoDB.html)

## Server Setup

Now that we have a user service that can interact with the database layer, we can set up our http
server. Our server comprises two main components. Routes and handlers. Routes are a
combination of http method and path that we accept requests at. We'll start by defining a handler,
then we'll attach it to a route, and finally we'll attach those routes to a server so we can invoke
them.

### Handler setup

In Go, HTTP handlers are used to process HTTP requests. Our handlers will implement the
`http.Handler` interface from the `net/http` package in the standard library (making them standard
library compatible). This interface requires a `ServeHTTP(w http.ResponseWriter, r *http.Request)`
method. Handlers can be also be defined as functions using the `http.HandlerFunc` type which allows
a function with the correct signature to be used as a handler. We'll define our handlers using the
function form.

In the `internal/handlers` package create a new `read_user.go` file. Copy the stub implementation
from below:

```go
func HandleReadUser(logger *slog.Logger) http.Handler {
	return http.HandlerFunc(func (w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		logger.InfoContext(ctx, "handling read user request")

		// Set the status code to 200 OK
		w.WriteHeader(http.StatusOK)

		id := r.PathValue("id")
		if id == "" {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}

		// Write the response body, simply echo the ID back out
		_, err := w.Write([]byte(id))
		if err != nil {
			// Handle error if response writing fails
			logger.ErrorContext(r.Context(), "failed to write response", slog.String("error", err.Error()))
			http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		}
	})
}
```

Notice that we're not defining a handler directly, rather we've defined a function that returns a
handler. This allows us to pass dependencies into the outer function and access them in our handler.

### Route setup

Now that we've defined a handler we'll create a function in our `internal/routes` package that will
be used to attach routes to an HTTP server. This will give us a single point in the future to see
all our routes and their handlers at a glance

In the `internal/routes/routes.go` file we'll define the function below:

```go
func AddRoutes(mux *http.ServeMux, logger *slog.Logger, usersService *services.UsersService) {
	// Read a user
	mux.Handle("GET /api/users/{id}", handlers.HandleReadUser(logger))
}
```

### Adding a server to main.go

With our service and handler defined we can add our server in `main.go`

Modify the `run` function in `main.go` to include the following below the dependencies we've
initialized along with code to create and run our server along with graceful shutdown logic:

```go
// Create a new users service
usersService := services.NewUsersService(logger, client)

// Create a serve mux to act as our route multiplexer
mux := http.NewServeMux()

// Add our routes to the mux
routes.AddRoutes(mux, logger, usersService)

// Create a new http server with our mux as the handler
httpServer := &http.Server{
	Addr:	net.JoinHostPort(cfg.Host, cfg.Port),
	Handler: mux,
}

errChan := make(chan error)

// Server run context
ctx, done := context.WithCancel(ctx)
defer done()

// Handle graceful shutdown with go routine on SIGINT
go func() {
	// create a channel to listen for SIGINT and then block until it is received
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt)
	<-sig

	logger.DebugContext(ctx, "Received SIGINT, shutting down server")

	// Create a context with a timeout to allow the server to shut down gracefully
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	// Shutdown the server. If an error occurs, send it to the error channel
	if err = httpServer.Shutdown(ctx); err != nil {
		errChan <- fmt.Errorf("[in main.run] failed to shutdown http server: %w", err)
		return
	}

	// Close the idle connections channel, unblocking `run()`
	done()
}()

// Start the http server
// 
// once httpServer.Shutdown is called, it will always return a
// http.ErrServerClosed error and we don't care about that error.
logger.InfoContext(ctx, "listening", slog.String("address", httpServer.Addr))
if err = httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
	return fmt.Errorf("[in main.run] failed to listen and serve: %w", err)
}

// block until the server is shut down or an error occurs
select {
case err = <-errChan:
	return err
case <-ctx.Done():
	return nil
}
```

Let's talk about what's going on here:
- First, we are initializing an instance of our `UserService` by passing the logger and database client to it.
- next, we are creating a server mux, passing it to `AddRoutes()` to add routes, and then creating an instance of the `http.Server` struct that includes the address of our web server and our mux.
- After that, we are setting up graceful shutdown logic. We do this by: 
    - Starting a Go routine and the immediately blocking until we receive a cancellation signal across a channel. This lets us wait until the server is starting to shut down before running any shutdown logic we need. 
    - After the signal is received, we create a cancellation context so that when we call `httpServer.Shutdown`, it can only run for a fixed amount of time. 
    - After all the shutdown logic has run, we call `done()` which will unblock our `run()` function and let us finally exit.
- Next, we start our server by calling httpServer.ListenAndServe() and checking any errors that are returned.
- Lastly, we use a `select` statement to block until the server has successfully shut down, or an error is sent across the `errChan` channel from our graceful shutdown Go routine.


If we run the application we should now see logs indicating our server is running including the
address. Try hitting our user endpoint! You can do this by using a tool like [postman](https://www.postman.com/), a VSCode extension like [REST Client](https://marketplace.visualstudio.com/items?itemName=humao.rest-client), or using `CURL` from the command line with the following command: 

```bash
curl -X GET localhost:8080/api/users/1
```
> Note, we are passing the ID of a user as the last value in the path. Try changing this value and see what happens!

Now try closing the application with `ctrl + C`. You should see some log messages in the terminal telling you that your graceful shutdown logic is running!

## Add Middleware

### Example: Adding a Logger Middleware

We often will need to modify or inspect requests and responses before or after they are handled by our handlers. Middleware is a way to do this. Middleware is a function that wraps an `http.Handler` and can modify the request or response before or after the handler is called. 

First, in `internal/middleware/middleware.go`, add the following line:

```go
// Middleware is a function that wraps a http.Handler.
type Middleware func(next http.Handler) http.Handler
```

This defines a custom type `Middleware` that is a function that takes an `http.Handler` and returns an `http.Handler`. This will allow us to define middleware that can wrap our handlers and modify the request or response before or after the handler is called.

Next, create the file `internal/middleware/logger.go` and add the following code:

```go
type wrappedWriter struct {
	http.ResponseWriter
	statusCode int
}

func (w *wrappedWriter) WriteHeader(statusCode int) {
	w.ResponseWriter.WriteHeader(statusCode)
	w.statusCode = statusCode
}

// Logger is a middleware that logs the request method, path, duration, and
// status code.
func Logger(logger *slog.Logger) Middleware {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()

			wrapped := &wrappedWriter{
				ResponseWriter: w,
				statusCode:     http.StatusOK,
			}

			next.ServeHTTP(wrapped, r)

			logger.InfoContext(
				r.Context(),
				"request completed",
				slog.String("method", r.Method),
				slog.String("path", r.URL.Path),
				slog.String("duration", time.Since(start).String()),
				slog.Int("status", wrapped.statusCode),
			)
		})
	}
}
````

There is a lot going on here, so lets break it down:
- We define a new type `wrappedWriter` that embeds an `http.ResponseWriter` and adds a `statusCode` field. This will allow us to track the status code of the response.
- We define a WriteHeader method on `wrappedWriter` that sets the `statusCode` field. This method overrides the method of the same name on the `http.ResponseWriter` interface. When a handler calls `WriteHeader` to set the status code of the response, it will actually call this method instead. We can use this to access the status code of the response.
- We define a `Logger` function that returns a `Middleware` function using a closure. This function takes a logger and returns a middleware function that logs the request method, path, duration, and status code of the response. We do this by wrapping the `http.Handler` that is passed to the middleware function and calling the `ServeHTTP` method on the wrapped handler. This allows us to run code before and after the handler is called. After the handler is called, we log the request method, path, duration, and status code of the response.

Next, in `cmd/api/main.go`, add the following code to the `run` function between the call to `routes.AddRoutes` and the definition of `httpServer` to add the logger middleware to the mux:

```go
// Wrap the mux with middleware
wrappedMux := middleware.Logger(logger)(mux)
```
Finally, update the `httpServer` definition to use the `wrappedMux` instead of the `mux`:

```go
// Create a new http server with our mux as the handler
httpServer := &http.Server{
	Addr:    net.JoinHostPort(cfg.Host, cfg.Port),
	Handler: wrappedMux,
}
```

If you run the application now and make a request to the existing endpoint, you should see logs indicating that the request method, path, duration, and status code are being logged. Try hitting the user endpoint again and see the logs that are generated!

### Assignment: Add recovery middleware

Now that you have seen how to create middleware in Go, try adding a recovery middleware to the application. Recovery middleware is used to recover from panics that occur in the application. Panics are a way to handle unrecoverable errors in Go, and can be used to recover from them and return a 500 status code to the client. Bellow are the criteria for the recovery middleware:
- The middleware should recover from panics that occur in the handlers or anything the handlers call.
- The middleware should log the error that caused the panic.
- The middleware should return a 500 status code to the client if a panic occurs.
- The Middleware should be called from `main.go` after the logger middleware is added.

Here are some resources you can use to learn more about panics and recovery in Go:
- [Go By Example: Recovery](https://gobyexample.com/recover)
- [Defer, Panic, and Recover](https://blog.golang.org/defer-panic-and-recover)

## Generating Swagger Docs

To add swagger to our application, we will need to provide swagger basic information to help generate our swagger documentation.
In `internal/routes/routes.go` add the following comments above the `AddRoutes` function:

```
// AddRoutes adds all routes to the provided mux.
//
// @title						Blog Service API
// @version						1.0
// @description					Practice Go API using the Standard Library and DynamoDB
// @termsOfService				http://swagger.io/terms/
// @contact.name				API Support
// @contact.url					http://www.swagger.io/support
// @contact.email				support@swagger.io
// @license.name				Apache 2.0
// @license.url					http://www.apache.org/licenses/LICENSE-2.0.html
// @host						localhost:8080
// @BasePath					/api
// @externalDocs.description    OpenAPI
// @externalDocs.url			https://swagger.io/resources/open-api/
```

For more detailed description on what each annotation does, please
see [Swaggo's Declarative Comments Format](https://github.com/swaggo/swag?tab=readme-ov-file#declarative-comments-format)

Next, we will add swagger comments for our handler. In `internal/handlers/read_user.go` add the
following comments above the `HandleReadUser` function:

```
// HandleReadUser returns an http.Handler that reads a user from storage.
//
//	@Summary		Read User
//	@Description	Read User by ID
//	@Tags			user
//	@Accept			json
//	@Produce		json
//	@Param			id  			path		string	true	"User ID"
//	@Success		200				{object}	userResponse
//	@Failure		400				{object}	string
//	@Failure		404				{object}	string
//	@Failure		500				{object}	string
//	@Router			/users/{id}  				[GET]
```

The above comments give swagger important information such as the path of the endpoint, request
parameters, request bodies, and response types. For more information about each annotation and
additional annotations you will need,
see [Swaggo Api Operation](https://github.com/swaggo/swag?tab=readme-ov-file#api-operation).

Almost there! We can now attach swagger to our project and generate the documentation based off our
comments. In the `internal/routes/routes.go`, update the `AddRoutes` function to match:

```go
func AddRoutes(mux *http.ServeMux, logger *slog.Logger, usersService *services.UsersService, baseURL string) {
	// Read a user
	mux.Handle("GET /api/users/{id}", handlers.HandleReadUser(logger))

	// swagger docs
	mux.Handle(
		"GET /swagger/",
		httpSwagger.Handler(httpSwagger.URL(baseURL+"/swagger/doc.json")),
	)
	logger.Info("Swagger running", slog.String("url", baseURL+"/swagger/index.html"))
}
```

We have now added a new handler that will show us our swagger docs in the browser.

Next, lets update our call to `AddRoutes()` in `main.run()` to include the base URL. It should now look like this:

```go
// Add our routes to the mux
routes.AddRoutes(
	mux,
	logger,
	usersService,
	fmt.Sprintf("http://%s:%s", cfg.Host, cfg.Port),
)
```

Next, generate the swagger documentation by running the following make command:

```bash
make swag-init
```

If successful, this should generate the swagger documentation for the project and place it in
`cmd/api/docs`.

Finally, go back to `internal/routes/routes.go` and add the following to your list of imports. Remember
to replace `[name]` with your name:

```
_ "github.com/[name]/blog/cmd/api/docs"
```

Congrats! You have now generated the swagger documentation for our application! We can now start up
our application and hit our endpoints!

We now have enough code to run the API end-to-end!

At this point, you should be able to run your application. You can do this using the make command
`make start-web-app` or using basic go build and run commands. If you encounter issues, ensure that
your database container is running in with colima, and that there are no syntax errors present in the
code.

Run the application and navigate to the swagger endpoint to see your collection of routes. You can do this by going to the following URL in a web browser: http://localhost:8080/swagger/index.html. Try
interacting with the read user route to verify it returns a response with our path parameter. Next,
we'll finish fleshing out that handler and create the rest of our handlers and routes.

## Injecting the user service into the read user handler

Now that we've verified our handler is properly handling http requests we'll implement some actual
read user logic. To do this, we need to make our user service accessible to the handler. We already
defined our handler as a closure, giving us a place to inject dependencies.

Instead of injecting the service directly we're going to leverage a features of Go and define and
inject a small interface.

In Go, interfaces are implemented implicitly. Which makes them a fantastic tool to abstract away the
details of a service at the point its used. Let's define the interface to see what we mean.

In `internal/handlers/read_user.go` add the following interface definition to the top of the file:

```go
// userReader represents a type capable of reading a user from storage and
// returning it or an error.
type userReader interface {
	ReadUser(ctx context.Context, id uuid.UUID) (models.User, error)
}
```

The Go community encourages this style of interface declaration. The interface is defined at the
point it's consumed, which allows us to narrow down the methods to only the single `ReadUser` method
we need. This greatly simplifies testing by simplifying the mock we need to create. This also gives
us additional type safety in that we've guaranteed that the handler for reading a user does not have
access to other functionality like deleting a user.

Now that we've defined our interface we can inject it. Add an argument for the interface to the
`HandleReadUser` function:

```go
func HandleReadUser(logger *slog.Logger, userReader userReader) http.Handler {
	// ... handler functionality
}
```

And update our handler invocation in the `internal/routes/routes.go` `AddRoutes` function:

```go
mux.Handle("GET /api/users/{id}", handlers.HandleReadUser(logger, usersService))
```

Notice that our user service can be supplied to `HandleReadUser` as it satisfies the `userReader`
interface. This style of accepting interfaces at implementation, and returning structs from
declaration is extremely popular in Go.

## Hiding the read user response type

A general best practice with developing APIs is to define request and response models separate from
our domain models. These models will be unexported and only used in the `handlers` package. This 
means a little bit of extra mapping, but keeps our domain model from leaking
out of our API. This also gives us some flexibility in the event a request or response doesn't
cleanly map to a domain model.

Creat a new file `internal/handlers/response.go` and add the following type definition:

```go
// userResponse represents the the output model for a user.
type userResponse struct {
	ID       uuid.UUID `json:"id"`
	Name     string    `json:"name"`
	Email    string    `json:"email"`
	Password string    `json:"password"`
}
```

## Reading the user and mapping it to a response

With our response type defined and our user service injected it's time to read our user model and
map it into a response. Update the `http.HandlerFunc` returned from `HandleReadUser` to the
following:
```go
func HandleReadUser(logger *slog.Logger, userReader userReader) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		logger.DebugContext(ctx, "Handling read user request")

		// Read id from path parameters
		idStr := r.PathValue("id")

		// Convert the ID from string to a UUID
		id, err := uuid.Parse(idStr)
		if err != nil {
			logger.ErrorContext(
				ctx,
				"failed to parse id from url",
				slog.String("id", idStr),
				slog.String("error", err.Error()),
			)

			http.Error(w, "Invalid ID", http.StatusBadRequest)
			return
		}

		// Read the user
		if err != nil {
			switch {
			case errors.Is(err, services.ErrNotFound):
				logger.ErrorContext(ctx, "user not found")
				http.Error(w, "User not found", http.StatusNotFound)
				
			default:
				logger.ErrorContext(
					ctx,
					"failed to read user",
					slog.String("error", err.Error()),
				)
				http.Error(w, "Internal Server Error", http.StatusInternalServerError)
			}

			return
		}

		// Convert our models.User domain model into a response model.
		response := userResponse{
			ID:       user.ID.UUID,
			Name:     user.Name,
			Email:    user.Email,
			Password: user.Password,
		}

		// Encode the response model as JSON
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		if err = json.NewEncoder(w).Encode(response); err != nil {
			logger.ErrorContext(
				ctx,
				"failed to encode response",
				slog.String("error", err.Error()),
			)

			http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		}
	})
}
````
Let's walk through the changes we made:
- We read the `id` from the path parameters and convert it to a `uuid.UUID` using the `uuid.Parse` function.
- We call the `ReadUser` method on the `userReader` interface to read the user from storage. If an error occurs, we log the error and return an appropriate status code.
  - Note how we use the `errors.Is` function to check if the error is a sentinel error inside our `err != nil` if statement. 
    - You should always check if an error is not `nil` before checking if it is a specific error. 
    - You should also always use `errors.Is` to check for sentinel errors, as apposed to an equality check with `err == ErrNamedError`.
- We convert the `models.User` domain model into a `userResponse` response model.
- We set the `Content-Type` header to `application/json` and the status code to `http.StatusOK`.
- We encode the response model as JSON and write it to the response body.

Now that we have defined what our response model is, we can update our swagger documentation to reflect this. Update the `@Success` annotation in `internal/handlers/read_user.go` to the following:

```go
//	@Success		200	{object}	userResponse
```

At this point we can rerun `make swag-init` and restart the server process and hit our read user endpoint again from swagger.

## Input model validation

One thing we still need is validation for incoming requests. We can create another single method
interface to help with this. Create a new `request.go` file in the `internal/handlers` package.
This will serve as a spot for shared request model types and validation logic.

Add the following interface and function to the file:

```go
package handlers

// validator is an object that can be validated.
type validator interface {
	// Valid checks the object and returns any
	// problems. If len(problems) == 0 then
	// the object is valid.
	Valid(ctx context.Context) (problems map[string]string)
}

// decodeValid decodes a model from a http request and performs validation
// on it.
func decodeValid[T validator](ctx context.Context, r *http.Request) (T, map[string]string, error) {
	var v T
  
	if err := json.NewDecoder(r.Body).Decode(&v); err != nil {
		return v, nil, fmt.Errorf("decode json: %w", err)
	}
  
	if problems := v.valid(ctx); len(problems) > 0 {
		return v, problems, fmt.Errorf("invalid %T: %d problems", v, len(problems))
	}
  
	return v, nil, nil
}
```

While writing handlers for requests that have input models we can use the code above to decode
models from the request body. Notice that `decodeValid` takes a generic that must implement the
`validator` interface. To call the function ensure the model you're attempting to decode implements
`validator`.

To demonstrate how this works, let's add a request model for creating a user. We will only add a single validation rule now, and you can add more rules later as needed. Inside the `request.go` file, add the following code:

```go
// createUserRequest represents the input model for creating a user.
type createUserRequest struct {
	Name     string `json:"name"`
	Email    string `json:"email"`
	Password string `json:"password"`
}

// valid checks the createUserRequest for any problems.
func (r createUserRequest) valid(ctx context.Context) map[string]string {
problems := make(map[string]string)

	// check that name is not blank
	if r.Name == "" {
		problems["name"] = "name is required"
	}

	return problems
}
```

You can see that we have defined our input model struct and then added a `valid` method to it. This method checks the input model for any problems and returns a map of problems. In this case, we are checking that the `name` field is not blank. This implicitly implements the `validator` interface. 

## Flesh out user CRUD routes / handlers

Now that we've fully fleshed out the read user endpoint we can create routes and handlers for each
of our other user CRUD operations.

| Operation   | Method   | Path              | Handler File     | Handler            |
|-------------|----------|-------------------|------------------|--------------------|
| Create User | `POST`   | `/api/users`      | `create_user.go` | `HandleCreateUser` |
| Update User | `PUT`    | `/api/users/{id}` | `update_user.go` | `HandleUpdateUser` |
| Delete User | `DELETE` | `/api/users/{id}` | `delete_user.go` | `HandleDeleteUser` |
| List Users  | `GET`    | `/api/users`      | `list_users.go`  | `HandleListUsers`  |

Remember to add the appropriate swagger annotations to each handler!

## Unit Testing

### Unit Testing Introduction

It is important with any language to test your code. Go make it easy to write unit tests, with a
robust built-in testing framework. For a brief introduction on unit testing in Go, check
out [this YouTube video](https://www.youtube.com/watch?v=FjkSJ1iXKpg).

### Unit Testing in This Tech Challenge

Unit testing is a required part of this tech challenge. There are no specific requirements for
exactly how you must write your unit tests, but keep the following in mind as you go through the
challenge:

- Go prefers to use table-driven, parallel unit tests. For more information on this, check out
  the [Go Wiki](https://go.dev/wiki/TableDrivenTests).
- Try to write your code in a way that is, among other things, easy to test. Go's preference for
  interfaces facilitates this nicely, and it can make your life easier when writing tests.
- There are already make targets set up to run unit tests. Specifically `check-coverage`. Feel free
  to modify these and add more if you would like to tailor them to your own preferences.

### Example: Handler unit test

Even though there are no requirements on how you write your tests, here is an example of a very basic unit test for a simple handler.

First, lets create a new handler. For this we are going to create a health check endpoint. To do this, create the file `internal/handlers/health.go` and add the following code:

```go
// healthResponse represents the response for the health check.
type healthResponse struct {
	Status string `json:"status"`
}

// HandleHealthCheck handles the health check endpoint
//
//	@Summary		Health Check
//	@Description	Health Check endpoint
//	@Tags			health
//	@Accept			json
//	@Produce		json
//	@Success		200		{object}	healthResponse
//	@Router			/health	[GET]
func HandleHealthCheck(logger *slog.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		logger.InfoContext(r.Context(), "health check called")
		
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(healthResponse{Status: "ok"})
	}
}
```

Next, lets register this handler with a route in side of the `internal/routes/routes.go` file by adding the following code to `AddRoutes()`:

```go
// health check
mux.Handle("GET /api/health", handlers.HandleHealthCheck(logger))
```

If you start the application and navigate to `http://localhost:8080/api/health` you should see a response with a status of `ok`.

Next, lets write a unit test for this handler. Create a new file `internal/handlers/health_test.go` and add the following unit test:

```go
func TestHandleHealthCheck(t *testing.T) {
	tests := map[string]struct {
		wantStatus int
		wantBody   string
	}{
		"happy path": {
			wantStatus: 200,
			wantBody:   `{"status":"ok"}`,
		},
	}
	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			// Create a new request
			req := httptest.NewRequest("GET", "/health", nil)

			// Create a new response recorder
			rec := httptest.NewRecorder()

			// Create a new logger
			logger := slog.Default()

			// Call the handler
			HandleHealthCheck(logger)(rec, req)

			// Check the status code
			assert.Equal(t, tc.wantStatus, rec.Code, "status code mismatch")

			// Check the body
			assert.JSONEq(t, tc.wantBody, strings.Trim(rec.Body.String(), "\n"), "body mismatch")
		})
	}
}
```

Let's break down what is happening in this test:
- We are creating a map of test cases. Each test case has a name, and a struct with the expected status code and body.
- We are then iterating over each test case and running a subtest for each one.
- In each subtest we are creating a new request, response recorder, and logger.
- We then call the handler with the logger and response recorder.
- Finally, we check the status code and body of the response recorder to ensure they match the expected values.

### Example: Service unit test

Now that we have looked at writing a unit test for a handler, lets look at writing a unit test for a service. For this example, we are going to write a unit test for the `ReadUser` method in the `UsersService` struct. This test will be a little more complex than the handler test, as we will need to make a mock for our DynamoDB client.

To start off, lets add an interface for our database client to the `internal/services/users.go` file. For now, we only need a `GetItem` method, but as you use more methods from the client you can add them to the interface.

```go
type dynamoClient interface {
	GetItem(ctx context.Context, params *dynamodb.GetItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error)
}
```

Next, lets update our `UsersService` struct and our constructor to take the database client as an interface:

```go
// UsersService is a service capable of performing CRUD operations for
// models.User models.
type UsersService struct {
	logger *slog.Logger
	client dynamoClient
}

// NewUsersService creates a new UsersService and returns a pointer to it.
func NewUsersService(logger *slog.Logger, client dynamoClient) *UsersService {
	return &UsersService{
		logger: logger,
		client: client,
	}
}
```

With the interface added, try running your application to see if everything still works (it should).

Next, lets work on setting up `mockery` to auto generate mocks for our interface. You can find documentation on `mockery` [here](https://vektra.github.io/mockery/latest/) You should have already installed `mockery` as part of the setup for this challenge. As such, we can move forward with generating the mock. To do this, we will need a `.mockey.yaml` file in the root of our project. Create that file and add the following code:

```yaml
with-expecter: true
packages:
  github.com/[your-name]/blog/internal/services:
    config:
      filename: "{{.InterfaceName | snakecase}}.go"
      dir: "{{.InterfaceDir}}/mock"
      mockname: "{{.InterfaceName | camelcase | firstUpper}}"
      outpkg: "mock"
      inpackage: false
    interfaces:
      dynamoClient:
```

> Note: Replace `[your-name]` with your GitHub username.

Let's break down what is happening in this file:

With the `.mockery.yaml` file in place, we can now generate the mock for our `dynamoClient` interface. To do this, run the following command:

```bash
make mock-gen
```

You should now see a new folder inside of `internal/services` called `mock` with a file called `dynamo_client.go`. This file contains the mock for our `dynamoClient` interface.

With our mocks creates, we can start our test! Create a new file `internal/services/users_test.go` and add the following code:

```go
func TestUsersService_ReadUser(t *testing.T) {
	testcases := map[string]struct {
		mockCalled	 bool
		mockInput	  []any
		mockOutput	 []any
		input		  uuid.UUID
		expectedOutput models.User
		expectedError  error
	}{
		"happy path": {
			mockCalled: true,
			mockInput: []any{
				context.TODO(),
				&dynamodb.GetItemInput{
					TableName: aws.String("BlogContent"),
					Key: map[string]types.AttributeValue{
						"PK": &types.AttributeValueMemberS{
							Value: "USER#d2eddb69-f92f-694d-450d-e7cdb6decce3",
						},
						"SK": &types.AttributeValueMemberS{
							Value: "USER#d2eddb69-f92f-694d-450d-e7cdb6decce3",
						},
					},
				},
			},
			mockOutput: []any{
				&dynamodb.GetItemOutput{
					Item: map[string]types.AttributeValue{
						"email":    &types.AttributeValueMemberS{Value: "testUser@example.com"},
						"GSI1PK":   &types.AttributeValueMemberS{Value: "USER"},
						"user_id":  &types.AttributeValueMemberS{Value: "d2eddb69-f92f-694d-450d-e7cdb6decce3"},
						"GSI1SK":   &types.AttributeValueMemberS{Value: "USER#d2eddb69-f92f-694d-450d-e7cdb6decce3"},
						"SK":       &types.AttributeValueMemberS{Value: "USER#d2eddb69-f92f-694d-450d-e7cdb6decce3"},
						"PK":       &types.AttributeValueMemberS{Value: "USER#d2eddb69-f92f-694d-450d-e7cdb6decce3"},
						"name":	    &types.AttributeValueMemberS{Value: "Test User"},
						"password": &types.AttributeValueMemberS{Value: "Test Password"},
					},
				},
				nil,
			},
			input: uuid.MustParse("d2eddb69-f92f-694d-450d-e7cdb6decce3"),
			expectedOutput: models.User{
				DynamoDBBase: models.DynamoDBBase{
					PK:     "USER#d2eddb69-f92f-694d-450d-e7cdb6decce3",
					SK:     "USER#d2eddb69-f92f-694d-450d-e7cdb6decce3",
					GSI1PK: "USER",
					GSI1SK: "USER#d2eddb69-f92f-694d-450d-e7cdb6decce3",
				},
				ID:       models.UUID{UUID: uuid.MustParse("d2eddb69-f92f-694d-450d-e7cdb6decce3")},
				Name:     "Test User",
				Email:    "testUser@example.com",
				Password: "Test Password",
			},
			expectedError: nil,
		},
	}
	for name, tc := range testcases {
		t.Run(name, func(t *testing.T) {
			mockClient := new(mock.DynamoClient)
			logger := slog.Default()

			if tc.mockCalled {
				mockClient.
					On("GetItem", tc.mockInput...).
					Return(tc.mockOutput...).
					Once()
			}

			userService := UsersService{
				logger: logger,
				client: mockClient,
			}

			output, err := userService.ReadUser(context.TODO(), tc.input)

			assert.Equal(t, tc.expectedError, err, "errors did not match")
			assert.Equal(t, tc.expectedOutput, output, "returned data does not match")

			if tc.mockCalled {
				mockClient.AssertExpectations(t)
			} else {
				mockClient.AssertNotCalled(t, "GetItem")
			}
		})
	}
}
```

There is a lot going on here, so let's break it down:
- When we create our test case struct, we define some fields that will control our mock and its behavior. These fields include:
  - `mockCalled`, to determine if the mock should be called
  - `mockInput`, to define the input arguments to the mock
  - `mockOutput`, to define the output of the mock
- Inside the test body, we create a new mock database connection. We can use the mock to define the expected behavior of the database query and tell the mocked database what to return.
- We then use the test case values to determine if the mock should be called, and if it should, we define the expected behavior of the mock.
- We then create a new instance of the `UsersService` and call the `ReadUser` method with the mocked database connection.
- Finally, we check the output and error of the method to ensure they match the expected values.

Now that we have defined a basic test for the happy path, try adding other test cases to the test to test other scenarios? What if the database call fails? What if the user does not exist? 

The testing patterns shown here should be enough for you to be able to fully test the rest of the application. 

## Next Steps

You are now ready to move on to the rest of the challenge. You can find the instructions for
that [here](./3-Challenge-Assignment.md).
