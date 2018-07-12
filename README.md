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


     
- Create the above directories in your local machine and also create empty .bal files.
- Then open the terminal and navigate to ballerina-with-ActiveMQ/guide and run Ballerina project initializing toolkit.

```
  $ ballerina init
```
# Developing the service

Let's get start with the implementation of the order_accepting_service.bal, which acts as a http endpoint which accept request from client and publish messages to a JMS destination.

