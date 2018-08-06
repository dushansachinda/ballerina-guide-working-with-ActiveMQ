# ballerina-guide-working-with-ActiveMQ

This Guide will illustrate how to configure ballerina services as a JMS producer (one way messaging, aka fire and forget mode) and JMS consumer with ActiveMQ message broker.

Let's consider a real world secenario where online order management system. Clients can place their orders, then Order accepting ballerina service will place that orders into a message broker queue, then Order dispatcher ballerina service will route them to a difference queues by considering the message content( it will check retail order or whole sale order), then respective ballerina services will consume the messages from each queue.


![alt text](https://github.com/tdkmalan/ballerina-guide-working-with-ActiveMQ/blob/master/JMS_bal_Service.png)


# The following are the sections available in this guide.

- What you'll build
- Prerequisites
- Implementation
- Testing
- Deployment
- Observability

# Prerequisites

- Ballerina Distribution
- Apache ActiveMQ 5.12.0

**Note -**
After installing the JMS broker, copy its .jar files into the <BALLERINA_HOME>/bre/lib folder
For ActiveMQ 5.12.0: Copy activemq-client-5.12.0.jar, geronimo-j2ee-management_1.1_spec-1.0.1.jar and hawtbuf-1.11.jar
A Text Editor or an IDE


# Implementation
If you want to skip the basics, you can download the git repo and directly move to the "Testing" section by skipping "Implementation" section.

# Create the project structure

Ballerina is a complete programming language that supports custom project structures. Use the following package structure for this guide.

```
ballerina-guide-working-with-ActiveMQ
 └── guide
      ├── order_accepting_service
      │    ├── order_accepting_service.bal
      │    └── tests
      │         └── order_accepting_service_test.bal
      │ 
      │── order_dispatcher_service
      │    └── order_dispatcher_service.bal
      │   	
      └── retail_order_process_service
      │    └── retail_order_process_service.bal
      │ 
      └── retail_order_process_service
	   └── wholesale_order_process_service.bal	
```
     
- Create the above directories in your local machine and also create empty .bal files.
- Then open the terminal and navigate to ballerina-guide-working-with-ActiveMQ/guide and run Ballerina project initializing toolkit.

```
  $ ballerina init
```
# Developing the service

Let's get start with the implementation of the "order_accepting_service.bal", which acts as a http endpoint which accept request from client and publish messages to a JMS destination. "order_dispatcher_service.bal" process the each message recieve to the Order_Queue and route orders to the destinations queues by considering their message content. "retail_order_process_service.bal" and "wholesale_order_process_service.bal" are listner services for the retail_Queue and Wholesale_Queue.

**order_accepting_service.bal**
```
import ballerina/log;
import ballerina/http;
import ballerina/jms;

// Type definition for a order
type Order record {
    string customerID;
    string productID;
    string quantity;
    string orderType;
};


// Initialize a JMS connection with the provider
// 'providerUrl' and 'initialContextFactory' vary based on the JMS provider you use
// 'Apache ActiveMQ' has been used as the message broker in this example
jms:Connection jmsConnection = new({
        initialContextFactory: "org.apache.activemq.jndi.ActiveMQInitialContextFactory",
        providerUrl: "tcp://localhost:61616"
    });

// Initialize a JMS session on top of the created connection
jms:Session jmsSession = new(jmsConnection, {
        acknowledgementMode: "AUTO_ACKNOWLEDGE"
    });

// Initialize a queue sender using the created session
endpoint jms:QueueSender jmsProducer {
    session:jmsSession,
    queueName:"Order_Queue"
};

// Service endpoint
endpoint http:Listener listener {
    port:9090
};

// Order Accepting Service, which allows users to place order online
@http:ServiceConfig {basePath:"/placeorder"}
service<http:Service> orderAcceptingService bind listener {
    // Resource that allows users to place an order 
    @http:ResourceConfig { methods: ["POST"], consumes: ["application/json"],
        produces: ["application/json"] }
    placeOrder(endpoint caller, http:Request request) {
        http:Response response;
        Order newOrder;
        json reqPayload;

        // Try parsing the JSON payload from the request
        match request.getJsonPayload() {
            // Valid JSON payload
            json payload => reqPayload = payload;
            // NOT a valid JSON payload
            any => {
                response.statusCode = 400;
                response.setJsonPayload({"Message":"Invalid payload - Not a valid JSON payload"});
                _ = caller -> respond(response);
                done;
            }
        }

        json customerID = reqPayload.customerID;
        json productID  = reqPayload.productID;
        json quantity = reqPayload.quantity;
        json orderType = reqPayload.orderType;

        // If payload parsing fails, send a "Bad Request" message as the response
        if (customerID == null || productID == null || quantity == null || orderType == null) {
            response.statusCode = 400;
            response.setJsonPayload({"Message":"Bad Request - Invalid payload"});
            _ = caller -> respond(response);
            done;
        }

        // Order details
        newOrder.customerID = customerID.toString();
        newOrder.productID = productID.toString();
        newOrder.quantity = quantity.toString();
        newOrder.orderType = orderType.toString();

    
        json responseMessage;
        var orderDetails = check <json>newOrder;
        // Create a JMS message
        jms:Message queueMessage = check jmsSession.createTextMessage(orderDetails.toString());
        // Send the message to the JMS queue
        _ = jmsProducer -> send(queueMessage);
        // Construct a success message for the response
        responseMessage = {"Message":"Your order is successfully placed"};
        log:printInfo("New order added to the JMS Queue; customerID: '" + newOrder.customerID +
                    "', productID: '" + newOrder.productID + "';");

        // Send response to the user
        response.setJsonPayload(responseMessage);
        _ = caller -> respond(response);
    }
}
```

**order_dispatcher_service.bal**

```
import ballerina/log;
import ballerina/jms;
import ballerina/io;


// Initialize a JMS connection with the provider
// 'Apache ActiveMQ' has been used as the message broker
jms:Connection conn = new({
        initialContextFactory: "org.apache.activemq.jndi.ActiveMQInitialContextFactory",
        providerUrl: "tcp://localhost:61616"
    });

// Initialize a JMS session on top of the created connection
jms:Session jmsSession = new(conn, {
        // Optional property. Defaults to AUTO_ACKNOWLEDGE
        acknowledgementMode: "AUTO_ACKNOWLEDGE"
    });

// Initialize a queue receiver using the created session
endpoint jms:QueueReceiver jmsConsumer {
    session:jmsSession,
    queueName:"Order_Queue"
};

// Initialize a retail queue sender using the created session
endpoint jms:QueueSender jmsProducerRetail {
    session:jmsSession,
    queueName:"Retail_Queue"
};

// Initialize a wholesale queue sender using the created session
endpoint jms:QueueSender jmsProducerWholesale {
    session:jmsSession,
    queueName:"Wholesale_Queue"
};


// JMS service that consumes messages from the JMS queue
// Bind the created consumer to the listener service
service<jms:Consumer> orderDispatcherService bind jmsConsumer {
    // Triggered whenever an order is added to the 'Order_Queue'
    onMessage(endpoint consumer, jms:Message message) {

        log:printInfo("New order received from the JMS Queue");
        // Retrieve the string payload using native function
        var orderDetails = check message.getTextMessageContent();
        log:printInfo("validating  Details: " + orderDetails);

        //Converting String content to JSON
        io:StringReader reader = new io:StringReader(orderDetails);
        json result = check reader.readJson();
        var closeResult = reader.close();
        //Retrieving JSON attribute "OrderType" value
        json orderType = result.orderType;

        //filtering and routing messages using message orderType
        if(orderType.toString() == "retail"){
              // Create a JMS message
                jms:Message queueMessage = check jmsSession.createTextMessage(orderDetails);
            // Send the message to the Retail JMS queue
             _ = jmsProducerRetail -> send(queueMessage);
             log:printInfo("New Retail order added to the Retail JMS Queue");
        }else if(orderType.toString() == "wholesale"){
            // Create a JMS message
                jms:Message queueMessage = check jmsSession.createTextMessage(orderDetails);
            // Send the message to the Wolesale JMS queue
             _ = jmsProducerWholesale -> send(queueMessage);
             log:printInfo("New Wholesale order added to the Wholesale JMS Queue");
        }else{    
            //ignoring invalid orderTypes  
        log:printInfo("No any valid order type recieved, ignoring the message, order type recieved - " + orderType.toString());
        }    
    }
}
```

**retail_order_process_service.bal**

```
import ballerina/log;
import ballerina/jms;


// Initialize a JMS connection with the provider
// 'Apache ActiveMQ' has been used as the message broker
jms:Connection conn = new({
        initialContextFactory: "org.apache.activemq.jndi.ActiveMQInitialContextFactory",
        providerUrl: "tcp://localhost:61616"
    });

// Initialize a JMS session on top of the created connection
jms:Session jmsSession = new(conn, {
        // Optional property. Defaults to AUTO_ACKNOWLEDGE
        acknowledgementMode: "AUTO_ACKNOWLEDGE"
    });

// Initialize a retail queue receiver using the created session
endpoint jms:QueueReceiver jmsConsumer {
    session:jmsSession,
    queueName:"Retail_Queue"
};

// JMS service that consumes messages from the JMS queue
// Bind the created consumer to the listener service
service<jms:Consumer> orderDispatcherService bind jmsConsumer {
    // Triggered whenever an order is added to the 'Order_Queue'
    onMessage(endpoint consumer, jms:Message message) {

        log:printInfo("New order received from the JMS Queue");
        // Retrieve the string payload using native function
        var orderDetails = check message.getTextMessageContent();
        log:printInfo("below retail order has been successfully processed");
        log:printInfo(orderDetails);
    }
}

```

**wholesale_order_process_service.bal**

```
import ballerina/log;
import ballerina/jms;


// Initialize a JMS connection with the provider
// 'Apache ActiveMQ' has been used as the message broker
jms:Connection conn = new({
        initialContextFactory: "org.apache.activemq.jndi.ActiveMQInitialContextFactory",
        providerUrl: "tcp://localhost:61616"
    });

// Initialize a JMS session on top of the created connection
jms:Session jmsSession = new(conn, {
        // Optional property. Defaults to AUTO_ACKNOWLEDGE
        acknowledgementMode: "AUTO_ACKNOWLEDGE"
    });

// Initialize a retail queue receiver using the created session
endpoint jms:QueueReceiver jmsConsumer {
    session:jmsSession,
    queueName:"Wholesale_Queue"
};

// JMS service that consumes messages from the JMS queue
// Bind the created consumer to the listener service
service<jms:Consumer> orderDispatcherService bind jmsConsumer {
    // Triggered whenever an order is added to the 'Order_Queue'
    onMessage(endpoint consumer, jms:Message message) {

        log:printInfo("New order received from the JMS Queue");
        // Retrieve the string payload using native function
        var orderDetails = check message.getTextMessageContent();
        log:printInfo("below wholesale order has been successfully processed");
        log:printInfo(orderDetails);

    }
}

```
# Testing

**innvoking the service**

- First, start the Apache ActiveMQ server by entering the following command in a terminal from <ActiveMQ_BIN_DIRECTORY>.
```
   $ ./activemq start
```
- run following commands in seperate terminals. 
```
   $ ballerina run order_accepting_service.bal
   $ ballerina run order_dispatcher_service.bal
   $ ballerina run retail_order_process_service.bal
   $ ballerina run wholesale_order_process_service.bal
```
- You can use below requests to simulate retail and wholesale order placing.
```
curl -d '{"customerID":"C001","productID":"P001","quantity":"4","orderType":"retail"}' -H "Content-Type: application/json" -X POST http://localhost:9090/placeOrder/place
 
curl -d '{"customerID":"C002","productID":"P002","quantity":"40000","orderType":"wholesale"}' -H "Content-Type: application/json" -X POST http://localhost:9090/placeOrder/place
 
```
# Deployment

Once you are done with the development, you can deploy the services using any of the methods that we listed below.

**Deploying locally**

As the first step, you can build Ballerina executable archives (.balx) of the services that we developed above. Navigate to  ballerina-guide-working-with-ActiveMQ/guide and run the following command.
```
   $ ballerina build
```
Once the .balx files are created inside the target folder, you can run them using the following command.
``
   $ ballerina run <Exec_Archive_File_Name>
``
The successful execution of a service will show us something similar to the following output.
```
ballerina: initiating service(s) in 'order_accepting_service.balx'
ballerina: initiating service(s) in 'order_dispatcher_service.balx'
ballerina: initiating service(s) in 'retail_order_process_service.balx'
ballerina: initiating service(s) in 'wholesale_order_process_service.balx'
```

**Deploying on Docker**

You can run the service that we developed above as a docker container. As Ballerina platform includes Ballerina_Docker_Extension, which offers native support for running ballerina programs on containers, you just need to put the corresponding docker annotations on your service code. Since this guide requires ActiveMQ as a prerequisite, you need a couple of more steps to configure it in docker container.

Please follow bleow steps.

- pull the ActiveMQ 5.12.0 docker image.
```
docker pull consol/activemq-5.12
```

- Launch the docker image
```
docker run -d --name='activemq' -it --rm -P consol/activemq-5.12:latest
```
- then execte ``` docker ps ``` command and check ActiveMQ container is up and ruuning.
```
f80fa55fe8c9        consol/activemq-5.12:latest   "/bin/sh -c '/opt/ap…"   8 hours ago         Up 8 hours          0.0.0.0:32779->1883/tcp, 0.0.0.0:32778->5672/tcp, 0.0.0.0:32777->8161/tcp, 0.0.0.0:32776->61613/tcp, 0.0.0.0:32775->61614/tcp, 0.0.0.0:32774->61616/tcp   activemq
```
Now let's see how we can deploy the order_acepting_service we developed above on docker. We need to import ballerinax/docker and use the annotation @docker:Config as shown below to enable docker image generation during the build time.


**order_acepting_service**

```
import ballerina/log;
import ballerina/http;
import ballerina/jms;
import ballerinax/docker;   




// Type definition for a order
type Order record {
    string customerID;
    string productID;
    string quantity;
    string orderType;
};


// Initialize a JMS connection with the provider
// 'providerUrl' and 'initialContextFactory' vary based on the JMS provider you use
// 'Apache ActiveMQ' has been used as the message broker in this example
jms:Connection jmsConnection = new({
        initialContextFactory: "org.apache.activemq.jndi.ActiveMQInitialContextFactory",
        providerUrl: "tcp://172.17.0.2:61616" 
    });

// Initialize a JMS session on top of the created connection
jms:Session jmsSession = new(jmsConnection, {
        acknowledgementMode: "AUTO_ACKNOWLEDGE"
    });

// Initialize a queue sender using the created session
endpoint jms:QueueSender jmsProducer {
    session:jmsSession,
    queueName:"Order_Queue"
};


@docker:Config {
    registry:"ballerina.guides.io",
    name:"order_accepting_service.bal",
    tag:"v1.0"
}

@docker:CopyFiles {
   files:[{source:"/home/krishan/Servers/apache-activemq-5.12.0/lib/geronimo-j2ee-management_1.1_spec-1.0.1.jar",
           target:"/ballerina/runtime/bre/lib"},{source:"/home/krishan/Servers/apache-activemq-5.12.0/lib/activemq-client-5.12.0.jar",
          target:"/ballerina/runtime/bre/lib"}] }


@docker:Expose{}
endpoint http:Listener listener {
    port:9090
};

// Order Accepting Service, which allows users to place order online
@http:ServiceConfig {basePath:"/placeOrder"}
service<http:Service> orderAcceptingService bind listener {
    // Resource that allows users to place an order 
    @http:ResourceConfig { methods: ["POST"], consumes: ["application/json"],
        produces: ["application/json"] }
    place(endpoint caller, http:Request request) {
        http:Response response;
        Order newOrder;
```
- You may configure other services the same way as above i.e order_dispatcher_service.bal, wholesale_order_process_service.bal, retail_order_process_service.bal what you may need to change @docker:Config names to the respective services

- @docker:Config annotation is used to provide the basic docker image configurations for the sample. @docker:CopyFiles is used to copy the JMS broker jar files into the ballerina bre/lib folder. You can provide multiple files as an array to field files of CopyFiles docker annotation. @docker:Expose {} is used to expose the port.

- Now you can build a Ballerina executable archive (.balx) of the service that we developed above, using the following command. This will also create the corresponding docker image using the docker annotations that you have configured above. Navigate to ballerina-guide-working-with-ActiveMQ/guide and run the following command.

```
ballerina build

```
Then run below commands to start docker containers
```
docker run -d -p 9090:9090 ballerina.guides.io/order_accepting_service.bal:v1.0
docker run -d  ballerina.guides.io/order_dispatcher_service.bal:v1.0
docker run -d  ballerina.guides.io/wholesale_order_process_service.bal:v1.0
docker run -d  ballerina.guides.io/retail_order_process_service.bal:v1.0
```

- Verify docker container is running with the use of $ docker ps. The status of the docker container should be shown as 'Up'.

- You can access the service using the same curl commands that we've used above.
```
curl -d '{"customerID":"C001","productID":"P001","quantity":"4","orderType":"retail"}' -H "Content-Type: application/json" -X POST http://localhost:9090/placeOrder/place
```
