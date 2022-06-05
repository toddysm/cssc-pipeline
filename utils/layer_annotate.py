import argparse
import json
import itertools
import sys
from dockerfile_parse import DockerfileParser

def main(args):
    """Parses the Dockerfile and the `docker inspect` output and assigns ownership to each layer
    of the Dockerfile produced. Layers that come from the base image are all assigned `upstream`
    ownership
    """

    # Load the Dockerfile
    dfp = DockerfileParser(args.dockerfile)

    # Load the content manifest
    with open(args.contentmanifest) as cm_file:
        cm = json.load(cm_file)

    ownership = {}
    cmd_count = len(dfp.structure)
    for layer in cm[0]['RootFS']['Layers'][::-1]:
        if dfp.structure[cmd_count - 1]['instruction'] == 'CMD':
            cmd_count = cmd_count - 1
        if dfp.structure[cmd_count - 1]['instruction'] != 'FROM':
            ownership[layer] = { 
                'instruction': dfp.structure[cmd_count - 1]['instruction'],
                'content': dfp.structure[cmd_count - 1]['content'],
                'owner': args.owner,
                'gitsha': args.gitsha,
                'gitrepo': args.gitrepo
                } 
        else:
            ownership[layer] = { 
                'instruction': dfp.structure[cmd_count - 1]['instruction'],
                'content': dfp.structure[cmd_count - 1]['content'],
                'owner': 'upstream',
                'gitsha': 'N/A',
                'gitrepo': 'N/A'
                }
        if cmd_count > 1:
            cmd_count = cmd_count - 1
    
    with open(args.outputfile, 'w') as of:
        json.dump(ownership, of)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Annotating Dockerfile layers with owner details")
    parser.add_argument('--dockerfile', '-d', default='Dockerfile', required=True, 
                help="The Dockerfile to parse", dest='dockerfile')
    parser.add_argument('--contentmanifest', '-c', default='inspect.json', required=True, 
                help="The Content Manifest (`docker inspect` output) to parse", dest='contentmanifest')
    parser.add_argument('--owner', '-o', required=True, 
                help="The owner to assign to the layers", dest='owner')
    parser.add_argument('--gitsha', '-s', required=True, 
                help="The Git SHA to assign to the layers", dest='gitsha')
    parser.add_argument('--gitrepo', '-r', required=True, 
                help="The Git repository to assign to the layers", dest='gitrepo')
    parser.add_argument('--outputfile', '-f', required=True, 
                help="The file to save the output to", dest='outputfile')
    args = parser.parse_args()

    # Print the arguments for debugging purposes
    print(args)

    sys.exit(main(args))

    