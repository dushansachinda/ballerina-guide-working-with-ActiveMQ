# ballerina-guide-working-with-ActiveMQ

This Guide will illustrate how to configure ballerina services as a JMS producer (one way messaging, aka fire and forget mode) and JMS consumer with ActiveMQ message broker.

Let's consider a real world secenario where online order management system. Clients can place their orders, then Order accepting ballerina service will place that orders into a message broker queue, then Order dispatcher ballerina service will route them to a difference queues by considering the message content( it will check retail order or whole sale order), then respective ballerina services will consume the messages from each queue.





# The following are the sections available in this guide.

- What you'll build
- Prerequisites
- Implementation
- Testing
- Deployment
- Observability
