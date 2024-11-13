// See https://aka.ms/new-console-template for more information
// Console.WriteLine("Hello, World!");

using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.IO;
using System.Runtime.InteropServices;
using Amazon;
using Amazon.SQS;
using Amazon.SQS.Model;
using System.Net.Http;
using System.Text.Json;

namespace Test
{
    public class Program
    {
        private static RegionEndpoint ServiceRegion = RegionEndpoint.APSoutheast1;
        private static readonly HttpClient httpClient = new HttpClient();
        static void Main(string[] args)
        {
            ServiceRegion = RegionEndpoint.GetBySystemName(args[0]);
            wFunc().Wait();
        }

        static async Task wFunc()
        {
            /* 
            The code below shows how to get temporary credentials from the enclave itself.
            The local vsock proxy redirects all 127.0.0.1:80 traffic to 3:8002 on the parent instance, where the IMDS proxy is running.
            */

            var responseString = await httpClient.GetStringAsync("http://127.0.0.1/latest/meta-data/iam/security-credentials/");
            Console.WriteLine(responseString);
            
            responseString = await httpClient.GetStringAsync(string.Format("http://127.0.0.1/latest/meta-data/iam/security-credentials/{0}", responseString));
            Console.WriteLine(responseString);
            using var jsonDocument = JsonDocument.Parse(responseString);
            var rootElement = jsonDocument.RootElement;

            var access_key = rootElement.GetProperty("AccessKeyId");
            var secret_access_key = rootElement.GetProperty("SecretAccessKey");
            var token = rootElement.GetProperty("Token");
            
            var awsCredentials = new Amazon.Runtime.SessionAWSCredentials(access_key.ToString(), secret_access_key.ToString(), token.ToString());
            var client = new AmazonSQSClient(awsCreden‌​tials, ServiceRegion);
            string queueName = "Source_Queue";
            string sendQueueName = "Target_Queue";

            var queueUrl = await GetQueueUrl(client, queueName);
            Console.WriteLine("The SQS receive queue URL is {0}", queueUrl);

            var sendQueueUrl = await GetQueueUrl(client, sendQueueName);
            Console.WriteLine("The SQS send queue URL is {0}", sendQueueUrl);

            while (true)
            {
                // Receive message from SQS
                var response = await ReceiveAndDeleteMessage(client, queueUrl);

                if (response.Messages.Count == 0)
                    continue;

                Console.WriteLine("Message Received from SQS Queue: {0} | MessageId: {1}", response.Messages[0].Body, response.Messages[0].MessageId);
                
                // Start a new thread to process the message
                var getData = Task.Factory.StartNew(async () => {
                    
                    var resp = string.Format("Message Received from Enclave | Processed Message with MessageId: {0}", response.Messages[0].MessageId);
                    
                    Dictionary<string, MessageAttributeValue> messageAttributes = new Dictionary<string, MessageAttributeValue>
                    {
                        { "TaskId", new MessageAttributeValue { DataType = "Number", StringValue = Task.CurrentId.ToString() } },
                    };

                    string messageBody = resp;

                    var sendMsgResponse = await SendMessage(client, sendQueueUrl, messageBody, messageAttributes);

                });
            }
        }

        static async Task<string> GetQueueUrl(IAmazonSQS client, string queueName)
        {
            var request = new GetQueueUrlRequest
            {
                QueueName = queueName
            };

            GetQueueUrlResponse response = await client.GetQueueUrlAsync(request);
            return response.QueueUrl;
        }

        static async Task<ReceiveMessageResponse> ReceiveAndDeleteMessage(IAmazonSQS client, string queueUrl)
        {
            // Receive a single message from the queue.
            var receiveMessageRequest = new ReceiveMessageRequest
            {
                AttributeNames = { "SentTimestamp" },
                MaxNumberOfMessages = 1,
                MessageAttributeNames = { "All" },
                QueueUrl = queueUrl,
                VisibilityTimeout = 0,
                WaitTimeSeconds = 0,
            };

            var receiveMessageResponse = await client.ReceiveMessageAsync(receiveMessageRequest);

            if (receiveMessageResponse.Messages.Count > 0)
            {
                // Delete the received message from the queue.
                var deleteMessageRequest = new DeleteMessageRequest
                {
                    QueueUrl = queueUrl,
                    ReceiptHandle = receiveMessageResponse.Messages[0].ReceiptHandle
                };

                await client.DeleteMessageAsync(deleteMessageRequest);
            }
            
            return receiveMessageResponse;
        }

        static async Task<SendMessageResponse> SendMessage(
            IAmazonSQS client,
            string queueUrl,
            string messageBody,
            Dictionary<string, MessageAttributeValue> messageAttributes)
        {
            var sendMessageRequest = new SendMessageRequest
            {
                DelaySeconds = 10,
                MessageAttributes = messageAttributes,
                MessageBody = messageBody,
                QueueUrl = queueUrl
            };

            var response = await client.SendMessageAsync(sendMessageRequest);
            Console.WriteLine("Sent a message with id : {0}", response.MessageId);

            return response;
        }

    }
}