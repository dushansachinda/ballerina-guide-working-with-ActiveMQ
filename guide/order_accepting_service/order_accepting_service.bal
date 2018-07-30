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
@http:ServiceConfig {basePath:"/placeOrder"}
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